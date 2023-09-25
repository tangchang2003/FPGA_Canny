module canny
(
	input			clk,
	input			rst_s,
	input    	[7:0] filter_out,
	output  reg [15:0]	canny_out,
	input			filter_de,
	input			filter_hs,
	input			filter_vs,
	output		canny_hs,
	output		canny_vs,
	output		canny_de
		
);
//双阈值的高低阈值
parameter THRESHOLD_LOW  = 10'd50;
parameter THRESHOLD_HIGH = 10'd100;

// shift_ram移位出口
wire [7:0] tap_0;
wire [7:0] tap_1;//输出端口

reg[9:0] Gx_1;//GX第一列计数
reg[9:0] Gx_3;
reg[9:0] Gy_1;
reg[9:0] Gy_3;

reg[10:0] Gx;//Gx Gy 做差分 求偏导
reg[10:0] Gy;

reg[20:0] sqrt_in;//计算梯度值的两个平方和
reg[9:0] sqrt_out;//开平方得到的梯度
reg[10:0] sqrt_rem;//开平方的余数
wire [20:0] sqrt_in_n;
wire [9:0] sqrt_out_n;
wire [10:0] sqrt_rem_n;
//对filter——de hs vs延迟
reg [5:0]hs_buf;
reg [5:0]vs_buf;
reg [5:0]de_buf;
wire sobel_de;
wire sobel_hs;
wire sobel_vs;

//9X9矩阵 sobel算子用
reg [7:0]  ma1_1;
reg [7:0]  ma1_2;
reg [7:0]  ma1_3;
reg [7:0]  ma2_1;
reg [7:0]  ma2_2;
reg [7:0]  ma2_3;
reg [7:0]  ma3_1;
reg [7:0]  ma3_2;
reg [7:0]  ma3_3;
//记录行上升沿，可以设置前两行全为8'h00,也可以随其自然
reg edge_de_a;
reg edge_de_b;
wire edge_de;
reg [9:0] row_cnt;
//-----非极大值抑制----
reg[1:0] sign;//Gx Gy  正 负
reg type; // Gx Gy 异号  同号

reg  path_one;
wire path_two;
reg  path_thr;
wire path_fou;//四个梯度方向
wire start;//判断，；xy轴方向有没有选中
reg [15:0] gra_path;//梯度幅值+方向+高低阈值状态
//--非极大值的ram出口
wire [15:0] tap_2;
wire [15:0] tap_3;
// 9x9矩阵，非极大值抑制用
reg [15:0]  max1_1;
reg [15:0]  max1_2;
reg [15:0]  max1_3;
reg [15:0]  max2_1;
reg [15:0]  max2_2;
reg [15:0]  max2_3;
reg [15:0]  max3_1;
reg [15:0]  max3_2;
reg [15:0]  max3_3;
//对sobel de hs vs 延迟3拍
reg [2:0]de_buf_n;
reg [2:0]hs_buf_n; 
reg [2:0]vs_buf_n;
//case四个方向选择
wire [3:0] path_se;
wire search;//八连通域判断是否有大于高阈值的点
 

shift_ram	shift_ram_inst (
	.aclr ( ~filter_vs),
	.clock ( clk),
	.clken ( filter_de),
	.shiftin ( filter_out ),//输入端口  第三行
	.shiftout (),//和tap——1一样的输出
	.taps0x ( tap_0 ),//第二行
	.taps1x ( tap_1 )//第一行
	);
	

//对矩阵第一行进行移位赋值
always @ (posedge clk or negedge rst_s)
begin
	if (!rst_s)
	{ma1_1,ma1_2,ma1_3} <= 24'd0;
	else if (filter_de)
	{ma1_1,ma1_2,ma1_3} <= {ma1_2,ma1_3,tap_1};
	else
	{ma1_1,ma1_2,ma1_3} <= {ma1_1,ma1_2,ma1_3};
end
//对矩阵第二行进行移位赋值
always @ (posedge clk or negedge rst_s)
begin
	if (!rst_s)
	{ma2_1,ma2_2,ma2_3} <= 24'd0;
	else if (filter_de)
	{ma2_1,ma2_2,ma2_3} <= {ma2_2,ma2_3,tap_0};
	else
	{ma2_1,ma2_2,ma2_3} <= {ma2_1,ma2_2,ma2_3};
end

//对矩阵第3行进行移位赋值
always @ (posedge clk or negedge rst_s)
begin
	if (!rst_s)
	{ma3_1,ma3_2,ma3_3} <= 24'd0;
	else if (filter_de)
	{ma3_1,ma3_2,ma3_3} <= {ma3_2,ma3_3,filter_out};
	else
	{ma3_1,ma3_2,ma3_3} <= {ma3_1,ma3_2,ma3_3};
end


//----------------Sobel Parameter--------------------------------------------
//      Gx             Gy				 Pixel
// [+1  0  -1]   [+1  +2  +1]   [ma1_1  ma1_2  ma1_3]
// [+2  0  -2]   [ 0   0   0]   [ma2_1  ma2_2  ma2_3]
// [+1  0  -1]   [-1  -2  -1]   [ma3_1  ma3_2  ma3_3]
//-------------------------------------------------------------
//将GX两列Gy 2列行先加  第一级流水线     
always @ (posedge clk or negedge rst_s)
begin
	if(!rst_s)
		begin
		Gx_1 <= 10'd0;
		Gx_3 <= 10'd0;
		end
	else
		begin
		Gx_1 <= {2'b00,ma1_1} + {1'b0,ma2_1,1'b0} +{2'b0,ma3_1};
		Gx_3 <= {2'b00,ma1_3} + {1'b0,ma2_3,1'b0} +{2'b0,ma3_3};
		end
end

always @ (posedge clk or negedge rst_s)
begin
	if(!rst_s)
		begin
		Gy_1 <= 10'd0;
		Gy_3 <= 10'd0;
		end
	else
		begin
		Gy_1 <= {2'b00,ma1_1} + {1'b0,ma1_2,1'b0} +{2'b0,ma1_3};
		Gy_3 <= {2'b00,ma3_1} + {1'b0,ma3_2,1'b0} +{2'b0,ma3_3};
		end
end
//---Gx1 Gx3；Gy1 Gy3  做差  差分 xy方向的偏导  再判断GX GY的正负 第二级    
always @(posedge clk or negedge rst_s)
begin
	if(!rst_s)
		begin
		Gx <= 11'd0;
		Gy <= 11'd0;
		sign <= 2'b00;
		end
	else
		begin
		Gx <= (Gx_1 >= Gx_3)? Gx_1 - Gx_3 : Gx_3 - Gx_1;
		Gy <= (Gy_1 >= Gy_3)? Gy_1 - Gy_3 : Gy_3 - Gy_1;
		sign[0] <= (Gx_1 >= Gx_3)? 1'b1 : 1'b0;//判断GX Gy 正负，1 正 0 负
		sign[1] <= (Gy_1 >= Gy_3)? 1'b1 : 1'b0;
		end
end
//第三级 平方和  + GX、GY异同号？+  GX GY 大小级别 + 梯度方向 
//求 Gx^2 Gy^2,提供给开方Ip计算梯度， //梯度的方向就是函数f(x,y)在这点增长最快的方向，梯度的模为方向导数的最大值。
// 梯度的摸 = (Gx^2 + Gy^2)开平方
always @(posedge clk or negedge rst_s)
begin
	if(!rst_s)
		sqrt_in <= 21'd0;
	else
		sqrt_in <= Gx*Gx + Gy*Gy;
end
assign sqrt_in_n = sqrt_in;

//对Gx Gy  正负的情况做分类  两类  异号 1 同号 0
always @ (posedge clk or negedge rst_s)
begin
	if(!rst_s)
	type <= 1'b0;
	else if (sign[0]^sign[1])
		type <= 1'b1;
	else
		type <= 1'b0;
end

// 对 GX GY 大小级别做判断，也就是 GX > GY*2.5 ？ Gy > GX*2.5?
// 符合 GX > GY*2.5 必定为x轴方向
always @ (posedge clk or negedge rst_s)
begin
	if (!rst_s)
		path_one <= 1'b0;
	else if(Gx > (Gy + Gy + Gy[10:1]))
		path_one <= 1'b1;
//这里有个失误点，本来Gx Gy是10位，但对于GY*2.5 超过1023时，只取低10位，进位消失，该if成立，就会出现XY轴同时为1
	else
		path_one <= 1'b0;
	
end
// 符合 Gy > Gx*2.5 必定为y轴方向
always @ (posedge clk or negedge rst_s)
begin
	if (!rst_s)
		path_thr <= 1'b0;
	else if(Gy > (Gx + Gx + Gx[10:1]))
		path_thr <= 1'b1;
	else
		path_thr <= 1'b0;
	
end

//  判断完 x y 轴方向 再判断两个对角方向
// 由于坐标轴原点在左上角 ------->  x
//			     |
//			     |
//			    y|
// 同号 为 \   异号为  /  (当然得在 X Y 轴 都不是的情况下)
assign start = (path_one | path_thr)? 1'b0 : 1'b1;
assign path_two = (start) ? type : 1'b0;
assign path_fou = (start) ? ~type: 1'b0;		
				
								
//开方IP组合逻辑，花的时间很少，送进去马上就得出数据，在下一个时钟赋给输出
sqrt	sqrt_inst (
	.radical ( sqrt_in_n ),
	.q ( sqrt_out_n ),
	.remainder ( sqrt_rem_n )
	);
//第四级
//开方得到梯度，再加上4个方向gra_path[13:10]
//提前对梯度进行双域值判断，以防进行非极大值抑制后又要来一个3X3的shift_ram
//意图在进行非极大值抑制的时候进行八连通域分析
//其实是伪双阈值，不再去判断大于高阈值的是不是极大值点，只要中间像素（小于高，大于低）周围
//有大于高阈值的点，就认为中间像素有效
//gra_path[15:14]高低阈值，gra_path[13:10]四个方向，gra_path[9:0]梯度幅值
always @(posedge clk or negedge rst_s)
begin
	if(!rst_s)
		gra_path <= 16'd0;
	else if (sqrt_out_n > THRESHOLD_HIGH)
		gra_path <= {1'b1,1'b0,path_fou,path_thr,path_two,path_one,sqrt_out_n};
	else if (sqrt_out_n > THRESHOLD_LOW)
		gra_path <= {1'b0,1'b1,path_fou,path_thr,path_two,path_one,sqrt_out_n};
	else
		gra_path <= 16'd0;
end
//对 hs vs de 进行适当的延迟，匹配VGA的时钟
always@(posedge clk or negedge rst_s)
begin
  if (!rst_s)
  begin
    hs_buf <= 6'd0 ;
    vs_buf <= 6'd0 ;
    de_buf <= 6'd0 ;
  end
  else
  begin
	   hs_buf <= {hs_buf[4:0], filter_hs} ;
	   vs_buf <= {vs_buf[4:0], filter_vs} ;
	   de_buf <= {de_buf[4:0], filter_de} ;
  end
end

assign sobel_hs = hs_buf[5] ;
assign sobel_vs = vs_buf[5] ;
assign sobel_de = de_buf[5] ;

//在计算一个像素的梯度和方向后，开始非极大值抑制

shift_ram_maximum 	shift_ram_maximum_m0 (
	.aclr (~sobel_vs),
	.clock ( clk),
	.clken ( sobel_de),
	.shiftin ( gra_path ),//输入端口  第三行
	.shiftout (),//和tap——1一样的输出
	.taps0x ( tap_2 ),//第二行
	.taps1x ( tap_3 )//第一行
	);

//对矩阵第一行进行移位赋值
always @ (posedge clk or negedge rst_s)
begin
	if (!rst_s)
	{max1_1,max1_2,max1_3} <= 48'd0;
	else if (sobel_de)
	{max1_1,max1_2,max1_3} <= {max1_2,max1_3,tap_3};
	else
	{max1_1,max1_2,max1_3} <= {max1_1,max1_2,max1_3};
end
//对矩阵第二行进行移位赋值
always @ (posedge clk or negedge rst_s)
begin
	if (!rst_s)
	{max2_1,max2_2,max2_3} <= 48'd0;
	else if (sobel_de)
	{max2_1,max2_2,max2_3} <= {max2_2,max2_3,tap_2};
	else
	{max2_1,max2_2,max2_3} <= {max2_1,max2_2,max2_3};
end

//对矩阵第3行进行移位赋值
always @ (posedge clk or negedge rst_s)
begin
	if (!rst_s)
	{max3_1,max3_2,max3_3} <= 48'd0;
	else if (sobel_de)
	{max3_1,max3_2,max3_3} <= {max3_2,max3_3,gra_path};
	else
	{max3_1,max3_2,max3_3} <= {max3_1,max3_2,max3_3};
end
//进行非极大值抑制

assign path_se = max2_2[13:10];//对于目标像素的梯度方向进行分配
assign search = max1_1[15] | max1_2[15] | max1_3[15] | max2_1[15] | max2_2[15] | max2_3[15] | max3_1[15] | max3_2[15] | max3_3[15];//搜寻目标像素周边是否包含梯度值大于高阈值的点，当然自身是高于的话，那么肯定为1  
always @ (posedge clk or negedge rst_s)
begin
	if(!rst_s)
	canny_out <= 16'h0000;
	else if (search &(row_cnt > 10'd5))
	begin
	case (path_se)	
		4'b0001:   
		canny_out <=((max2_2[9:0]>= max2_1[9:0])&(max2_2[9:0]>= max2_3[9:0]))?16'hffff:16'h0000;
		4'b0010:  
		canny_out <=((max2_2[9:0]>= max1_3[9:0])&(max2_2[9:0]>= max3_1[9:0]))?16'hffff:16'h0000;	
		4'b0100: 	
		canny_out <=((max2_2[9:0]>= max1_2[9:0])&(max2_2[9:0]>= max3_2[9:0]))?16'hffff:16'h0000;	
		4'b1000:			
		canny_out <=((max2_2[9:0]>= max1_1[9:0])&(max2_2[9:0]>= max3_3[9:0]))?16'hffff:16'h0000;
		default:
		canny_out <= 16'h0000;
	endcase
	end
	else
		canny_out <= 16'h0000;
end

always@(posedge clk or negedge rst_s)
begin
  if (!rst_s)
  begin
    hs_buf_n <= 3'd0 ;
    vs_buf_n <= 3'd0 ;
    de_buf_n <= 3'd0 ;
  end
  else
  begin
	   hs_buf_n <= {hs_buf_n[1:0], sobel_hs} ;
	   vs_buf_n <= {vs_buf_n[1:0], sobel_vs} ;
	   de_buf_n <= {de_buf_n[1:0], sobel_de} ;
  end
end

assign canny_hs = hs_buf_n[2] ;
assign canny_vs = vs_buf_n[2] ;
assign canny_de = de_buf_n[2] ;


//检测行标志信号上升沿
always @ (posedge clk or negedge rst_s)
begin
		if (!rst_s)
			begin
			edge_de_a <= 1'b0;
			edge_de_b <= 1'b0;
			end
		else
			begin
			edge_de_a <= filter_de;
			edge_de_b <= edge_de_a;
			end
end
assign edge_de = edge_de_a & ~edge_de_b;
//记录行数，对前4行进行特殊处理
always @ (posedge clk or negedge rst_s)
begin
		if (!rst_s)
			row_cnt <= 10'd0;
		else if(~canny_vs)
			row_cnt <= 10'd0;
		else if(edge_de)
			row_cnt <= row_cnt + 1'b1;
		else
			row_cnt <= row_cnt;
end




endmodule



