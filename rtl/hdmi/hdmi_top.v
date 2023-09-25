

module hdmi_top(
	input 		   hdmi_clk     ,
	input 		   hdmi_clk_5   ,
	input 		   rst_n        ,
	
	input  [15:0]  rd_data      ,
	output 		   rd_en        ,
	
	output [10:0 ] pixel_xpos   ,  //像素点横坐标
	output [10:0 ] pixel_ypos   ,  //像素点纵坐标 
	output [10:0]  h_disp       ,
	output [10:0]  v_disp       ,
	output         video_vs     ,
	
	//HDMI接口
   output         tmds_clk_p   ,  // TMDS 时钟通道
   output         tmds_clk_n   ,
   output [2:0]   tmds_data_p  ,  // TMDS 数据通道
   output [2:0]   tmds_data_n

);

//wire define

wire [23:0 ] video_rgb     ;
wire         video_hs      ;
wire         video_de      ;

//例化视频显示驱动模块
video_driver u_video_driver(
    .pixel_clk      (hdmi_clk    ),
    .sys_rst_n      (rst_n       ),

    .video_hs       (video_hs    ),
    .video_vs       (video_vs    ),
    .video_de       (video_de    ),
    .video_rgb      (video_rgb   ),
    .data_req       (rd_en       ),
    .pixel_xpos     (pixel_xpos  ),
    .pixel_ypos     (pixel_ypos  ),
	 .h_disp         (h_disp      ),
	 .v_disp         (v_disp      ),
    .video_rgb_565  (rd_data     )
    );

//例化HDMI驱动模块
dvi_transmitter_top u_rgb2dvi_0(
    .pclk           (hdmi_clk   ),
    .pclk_x5        (hdmi_clk_5 ),
    .reset_n        (rst_n      ),
                
    .video_din      (video_rgb  ),
    .video_hsync    (video_hs   ), 
    .video_vsync    (video_vs   ),
    .video_de       (video_de   ),
                
    .tmds_clk_p     (tmds_clk_p ),
    .tmds_clk_n     (tmds_clk_n ),
    .tmds_data_p    (tmds_data_p),
    .tmds_data_n    (tmds_data_n)
    );
	 
endmodule