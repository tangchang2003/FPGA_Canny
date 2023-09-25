//****************************************Copyright (c)***********************************//
//原子哥在线教学平台：www.yuanzige.com
//技术支持：www.openedv.com
//淘宝店铺：http://openedv.taobao.com
//关注微信公众平台微信号："正点原子"，免费获取ZYNQ & FPGA & STM32 & LINUX资料。
//版权所有，盗版必究。
//Copyright(C) 正点原子 2018-2028
//All rights reserved
//----------------------------------------------------------------------------------------
// File name:           ov5640_hdmi_sobel
// Last modified Date:  2021/05/06 9:19:08
// Last Version:        V1.0
// Descriptions:        基于OV5640摄像头的边缘检测
//                      
//----------------------------------------------------------------------------------------
// Created by:          正点原子
// Created date:        2021/05/06 9:19:08
// Version:             V1.0
// Descriptions:        The original version
//
//----------------------------------------------------------------------------------------
//****************************************************************************************//

module ov5640_hdmi_sobel(    
    input         sys_clk    ,  //系统时钟
    input         sys_rst_n  ,  //系统复位，低电平有效
    //摄像头 
    input         cam_pclk   ,  //cmos 数据像素时钟
    input         cam_vsync  ,  //cmos 场同步信号
    input         cam_href   ,  //cmos 行同步信号
    input  [7:0]  cam_data   ,  //cmos 数据  
    output        cam_rst_n  ,  //cmos 复位信号，低电平有效
    output        cam_pwdn   ,  //cmos 电源休眠模式选择信号
    output        cam_scl    ,  //cmos SCCB_SCL线
    inout         cam_sda    ,  //cmos SCCB_SDA线
    //SDRAM 
    output        sdram_clk  ,  //SDRAM 时钟
    output        sdram_cke  ,  //SDRAM 时钟有效
    output        sdram_cs_n ,  //SDRAM 片选
    output        sdram_ras_n,  //SDRAM 行有效
    output        sdram_cas_n,  //SDRAM 列有效
    output        sdram_we_n ,  //SDRAM 写有效
    output [1:0]  sdram_ba   ,  //SDRAM Bank地址
    output [1:0]  sdram_dqm  ,  //SDRAM 数据掩码
    output [12:0] sdram_addr ,  //SDRAM 地址
    inout  [15:0] sdram_data ,  //SDRAM 数据    
    //HDMI接口
    output        tmds_clk_p,   // TMDS 时钟通道
    output        tmds_clk_n,
    output [2:0]  tmds_data_p,  // TMDS 数据通道
    output [2:0]  tmds_data_n
    );

//parameter define
parameter SLAVE_ADDR    = 7'h3c          ; //OV5640的器件地址7'h3c
parameter BIT_CTRL      = 1'b1           ; //OV5640的字节地址为16位  0:8位 1:16位
parameter CLK_FREQ      = 27'd50_000_000 ; //i2c_dri模块的驱动时钟频率 
parameter I2C_FREQ      = 18'd250_000    ; //I2C的SCL时钟频率,不超过400KHz
parameter V_CMOS_DISP   = 11'd800        ; //CMOS分辨率--行
parameter H_CMOS_DISP   = 11'd1280       ; //CMOS分辨率--列	
parameter TOTAL_H_PIXEL = 13'd2570       ; //CMOS分辨率--行
parameter TOTAL_V_PIXEL = 13'd980        ;

//wire define
wire        clk_100m           ;  //100mhz时钟,SDRAM操作时钟
wire        clk_100m_shift     ;  //100mhz时钟,SDRAM相位偏移时钟
wire        clk_50m            ;
wire        hdmi_clk           ;  
wire        hdmi_clk_5         ;  
wire        locked             ;
wire        locked_hdmi        ;
wire        rst_n              ;
wire        sys_init_done      ;  //系统初始化完成(sdram初始化+摄像头初始化)
wire        i2c_exec           ;  //I2C触发执行信号
wire [23:0] i2c_data           ;  //I2C要配置的地址与数据(高8位地址,低8位数据)          
wire        i2c_done           ;  //I2C寄存器配置完成信号
wire        i2c_dri_clk        ;  //I2C操作时钟
wire [ 7:0] i2c_data_r         ;  //I2C读出的数据
wire        i2c_rh_wl          ;  //I2C读写控制信号
wire        cam_init_done      ;  //摄像头初始化完成                         
wire        wr_en              ;  //sdram_ctrl模块写使能
wire [15:0] wr_data            ;  //sdram_ctrl模块写数据
wire        rd_en              ;  //sdram_ctrl模块读使能
wire [15:0] rd_data            ;  //sdram_ctrl模块读数据
wire        sdram_init_done    ;  //SDRAM初始化完成
wire [10:0] pixel_xpos_w       ;  //HDMI横坐标
wire [10:0] pixel_ypos_w       ;  //HDMI纵坐标
wire        post_frame_vsync   ;  //处理后的场信号
wire        post_frame_hsync   ;  //处理后的行信号
wire        post_frame_de      ;  //处理后的数据使能  
wire [15:0] post_rgb           ;  //处理后的数据 

//*****************************************************
//**                    main code
//*****************************************************

assign  rst_n = sys_rst_n & locked & locked_hdmi;
//系统初始化完成：SDRAM和摄像头都初始化完成
//避免了在SDRAM初始化过程中向里面写入数据
assign  sys_init_done = sdram_init_done & cam_init_done;
//电源休眠模式选择 0：正常模式 1：电源休眠模式
assign  cam_pwdn  = 1'b0;
assign  cam_rst_n = 1'b1;

//锁相环
pll u_pll(
    .areset             (~sys_rst_n),
    .inclk0             (sys_clk),            
    .c0                 (clk_100m),
    .c1                 (clk_100m_shift),  
    .c2                 (clk_50m),	 
    .locked             (locked)
    );

pll_hdmi	pll_hdmi_inst (
	.areset 			( ~sys_rst_n  ),
	.inclk0 			( sys_clk     ),
	.c0 				( hdmi_clk    ),//hdmi pixel clock 71Mhz
	.c1 				( hdmi_clk_5  ),//hdmi pixel clock*5 355Mhz
	.locked 			( locked_hdmi )
	);
	 
//I2C配置模块
i2c_ov5640_rgb565_cfg u_i2c_cfg(
    .clk                (i2c_dri_clk),
    .rst_n              (rst_n      ),
            
    .i2c_exec           (i2c_exec   ),
    .i2c_data           (i2c_data   ),
    .i2c_rh_wl          (i2c_rh_wl  ),      //I2C读写控制信号
    .i2c_done           (i2c_done   ), 
    .i2c_data_r         (i2c_data_r ),   
                
    .cmos_h_pixel       (H_CMOS_DISP  ),    //CMOS水平方向像素个数
    .cmos_v_pixel       (V_CMOS_DISP  ) ,   //CMOS垂直方向像素个数
    .total_h_pixel      (TOTAL_H_PIXEL),    //水平总像素大小
    .total_v_pixel      (TOTAL_V_PIXEL),    //垂直总像素大小
        
    .init_done          (cam_init_done) 
    );    

//I2C驱动模块
i2c_dri #(
    .SLAVE_ADDR         (SLAVE_ADDR    ),    //参数传递
    .CLK_FREQ           (CLK_FREQ      ),              
    .I2C_FREQ           (I2C_FREQ      ) 
    )
u_i2c_dr(
    .clk                (clk_50m       ),
    .rst_n              (rst_n         ),

    .i2c_exec           (i2c_exec      ),   
    .bit_ctrl           (BIT_CTRL      ),   
    .i2c_rh_wl          (i2c_rh_wl     ),     //固定为0，只用到了IIC驱动的写操作   
    .i2c_addr           (i2c_data[23:8]),   
    .i2c_data_w         (i2c_data[7:0] ),   
    .i2c_data_r         (i2c_data_r    ),   
    .i2c_done           (i2c_done      ),    
    .scl                (cam_scl       ),   
    .sda                (cam_sda       ),
    .dri_clk            (i2c_dri_clk   )       //I2C操作时钟
    );

//CMOS图像数据采集模块
cmos_capture_data u_cmos_capture_data(         //系统初始化完成之后再开始采集数据 
    .rst_n              (rst_n & sys_init_done),
    
    .cam_pclk           (cam_pclk ),
    .cam_vsync          (cam_vsync),
    .cam_href           (cam_href ),
    .cam_data           (cam_data ),         
    
    .cmos_frame_vsync   (cmos_frame_vsync),
    .cmos_frame_href    (cmos_frame_href),
    .cmos_frame_valid   (wr_en    ),      //数据有效使能信号
    .cmos_frame_data    (wr_data  )       //有效数据 
    );
	 
 //图像处理模块
vip u_vip(
    //module clock
    .clk              (cam_pclk),           // 时钟信号
    .rst_n            (rst_n    ),          // 复位信号（低有效）
    //图像处理前的数据接口
    .pre_frame_vsync  (cmos_frame_vsync   ),
    .pre_frame_hsync  (cmos_frame_href   ),
    .pre_frame_de     (wr_en   ),
    .pre_rgb          (wr_data),
    .xpos             (pixel_xpos_w   ),
    .ypos             (pixel_ypos_w   ),
    //图像处理后的数据接口
    .post_frame_vsync (post_frame_vsync ),  // 场同步信号
    .post_frame_hsync ( ),                  // 行同步信号
    .post_frame_de    (post_frame_de ),     // 数据输入使能
    .post_rgb         (post_rgb)            // RGB565颜色数据

); 		 

//SDRAM 控制器顶层模块,封装成FIFO接口
//SDRAM 控制器地址组成: {bank_addr[1:0],row_addr[12:0],col_addr[8:0]}
sdram_top u_sdram_top(
    .ref_clk            (clk_100m),         //sdram 控制器参考时钟
    .out_clk            (clk_100m_shift),   //用于输出的相位偏移时钟
    .rst_n              (rst_n),            //系统复位
                                            
    //用户写端口                              
    .wr_clk             (cam_pclk),         //写端口FIFO: 写时钟
    .wr_en              (post_frame_de),    //写端口FIFO: 写使能
    .wr_data            (post_rgb),         //写端口FIFO: 写数据	 
	 
    .wr_min_addr        (24'd0),            //写SDRAM的起始地址
    .wr_max_addr        (V_CMOS_DISP*H_CMOS_DISP-1),   //写SDRAM的结束地址
    .wr_len             (10'd512),          //写SDRAM时的数据突发长度
    .wr_load            (~rst_n),           //写端口复位: 复位写地址,清空写FIFO
                                            
    //用户读端口                              
    .rd_clk             (hdmi_clk),         //读端口FIFO: 读时钟
    .rd_en              (rd_en),            //读端口FIFO: 读使能
    .rd_data            (rd_data),          //读端口FIFO: 读数据
    .rd_min_addr        (24'd0),            //读SDRAM的起始地址
    .rd_max_addr        (V_CMOS_DISP*H_CMOS_DISP-1),   //读SDRAM的结束地址
    .rd_len             (10'd512),          //从SDRAM中读数据时的突发长度
    .rd_load            (~rst_n),           //读端口复位: 复位读地址,清空读FIFO
                                                
    //用户控制端口                                
    .sdram_read_valid   (1'b1),             //SDRAM 读使能
    .sdram_pingpang_en  (1'b1),             //SDRAM 乒乓操作使能
    .sdram_init_done    (sdram_init_done),  //SDRAM 初始化完成标志
                                            
    //SDRAM 芯片接口                                
    .sdram_clk          (sdram_clk),        //SDRAM 芯片时钟
    .sdram_cke          (sdram_cke),        //SDRAM 时钟有效
    .sdram_cs_n         (sdram_cs_n),       //SDRAM 片选
    .sdram_ras_n        (sdram_ras_n),      //SDRAM 行有效
    .sdram_cas_n        (sdram_cas_n),      //SDRAM 列有效
    .sdram_we_n         (sdram_we_n),       //SDRAM 写有效
    .sdram_ba           (sdram_ba),         //SDRAM Bank地址
    .sdram_addr         (sdram_addr),       //SDRAM 行/列地址
    .sdram_data         (sdram_data),       //SDRAM 数据
    .sdram_dqm          (sdram_dqm)         //SDRAM 数据掩码
    );

//例化HDMI顶层模块
hdmi_top u_hdmi_top(
    .hdmi_clk       (hdmi_clk   ),
    .hdmi_clk_5     (hdmi_clk_5 ),
    .rst_n          (rst_n      ),
                
    .rd_data        (rd_data    ),
    .rd_en          (rd_en      ), 
    .h_disp         (),	 
    .v_disp         (),
    .pixel_xpos     (pixel_xpos_w),
    .pixel_ypos     (pixel_ypos_w),
    .video_vs       (),	 
    .tmds_clk_p     (tmds_clk_p ),
    .tmds_clk_n     (tmds_clk_n ),
    .tmds_data_p    (tmds_data_p),
    .tmds_data_n    (tmds_data_n)
    );	 

endmodule 