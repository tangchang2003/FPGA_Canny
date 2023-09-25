

module  video_display(
    input                pixel_clk,
    input                sys_rst_n,
    
    input        [10:0]  pixel_xpos,  //鍍忕礌鐐规í鍧愭爣
    input        [10:0]  pixel_ypos,  //鍍忕礌鐐圭旱鍧愭爣
	 input        [15:0]  cmos_data ,
	 output  reg          rd_req    ,
    output  reg  [23:0]  pixel_data   //鍍忕礌鐐规暟鎹);
);
//parameter define
parameter  H_DISP = 11'd1280;                       //鍒嗚鲸鐜団€斺€旇
parameter  V_DISP = 11'd720;                        //鍒嗚鲸鐜団€斺€斿垪
    
//*****************************************************
//**                    main code
//*****************************************************

//鏍规嵁褰撳墠鍍忕礌鐐瑰潗鏍囨寚瀹氬綋鍓嶅儚绱犵偣棰滆壊鏁版嵁锛屽湪灞忓箷涓婃樉绀哄僵鏉always @(posedge pixel_clk ) begin
always @(posedge pixel_clk ) begin
    if (!sys_rst_n)begin
	     rd_req     <=1'b0;
        pixel_data <= 24'd0;
	 end
	 
    else if((pixel_xpos >= 0) && (pixel_xpos < 1024)&&(pixel_ypos>=0)&&(pixel_ypos<768))begin
	         rd_req     <=1'b1;
            pixel_data <= {cmos_data[15:11],3'b000,cmos_data[10:5],2'b00,
                    cmos_data[4:0],3'b000};
	 end 
	 
    else begin
		  rd_req     <=1'b0;
        pixel_data <= 23'd0;
    end
end

endmodule