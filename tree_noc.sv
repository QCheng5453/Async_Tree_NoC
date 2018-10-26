`timescale 1ns/1ns
import SystemVerilogCSP::*;

module child_scheme (interface c_in, interface c_out, interface p_out);
    parameter reg[3:0] ADDRESS = 4'b0000;
    parameter reg[3:0] MASK = 4'b1110;
    parameter PACKET_WIDTH = 16;
    logic [PACKET_WIDTH-1:0] packet;

    always begin
        c_in.Receive(packet);
        // router print
        // $display("--------------------------------------------------------------------------------");
        // $display("(Time: \t\t %t),\t Router receiving packet", $time);
        // $display("Router -- %b : %b", ADDRESS, MASK);
        // $display("packet: \t%b, data: \t%b, destination: \t%b", packet, packet[3:0], packet[7:4]);

        if ((packet[7:4] & MASK) == ADDRESS) c_out.Send(packet);
        else p_out.Send(packet);
    end
endmodule

module parent_scheme (interface p_in, interface c1_out, interface c2_out);
    parameter reg[3:0] ADDRESS = 4'b0000;
    parameter reg[3:0] MASK = 4'b1110;
    parameter PACKET_WIDTH = 16;
    logic [PACKET_WIDTH-1:0] packet;

    always begin
        p_in.Receive(packet);

        // $display("--------------------------------------------------------------------------------");
        // $display("(Time: \t\t %t),\t Router receiving packet", $time);
        // $display("Router -- %b : %b", ADDRESS, MASK);
        // $display("packet: \t%b, data: \t%b, destination: \t%b", packet, packet[3:0], packet[7:4]);

        case (MASK)
            4'b1110: begin
                if (packet[4]) c2_out.Send(packet);
                else c1_out.Send(packet);
            end
            4'b1100: begin
                if (packet[5]) c2_out.Send(packet);
                else c1_out.Send(packet);
            end
            4'b1000: begin
                if (packet[6]) c2_out.Send(packet);
                else c1_out.Send(packet);
            end
            default: ;
        endcase
    end
endmodule

module arbiter_merge (interface l0, interface l1, interface o);
    parameter PACKET_WIDTH = 16;
    logic [PACKET_WIDTH-1:0] packet;
    logic winner;

    always begin
        wait(l0.status == 2 || l1.status == 2);
        if(l0.status == 2 && l1.status == 2) begin
            winner = $random();
            if (winner) l0.Receive(packet);
            else l1.Receive(packet);
        end
        else if (l0.status == 2) begin
            l0.Receive(packet);
        end
        else if (l1.status == 2) begin
            l1.Receive(packet);
        end
        # 4; // fl
        o.Send(packet);
    end
endmodule

module router (interface p_in, interface c1_in, interface c2_in, interface p_out, interface c1_out, interface c2_out);
    parameter PACKET_WIDTH = 16;
    parameter reg[3:0] ADDRESS = 4'b0000;
    parameter reg[3:0] MASK = 4'b1110;

    Channel #(.WIDTH(PACKET_WIDTH), .hsProtocol(P4PhaseBD)) p_c1 ();
    Channel #(.WIDTH(PACKET_WIDTH), .hsProtocol(P4PhaseBD)) p_c2 ();
    Channel #(.WIDTH(PACKET_WIDTH), .hsProtocol(P4PhaseBD)) c1_p ();
    Channel #(.WIDTH(PACKET_WIDTH), .hsProtocol(P4PhaseBD)) c1_c2 ();
    Channel #(.WIDTH(PACKET_WIDTH), .hsProtocol(P4PhaseBD)) c2_p ();
    Channel #(.WIDTH(PACKET_WIDTH), .hsProtocol(P4PhaseBD)) c2_c1 ();

    parent_scheme #(.ADDRESS(ADDRESS), .MASK(MASK), .PACKET_WIDTH(PACKET_WIDTH)) ps(p_in, p_c1, p_c2);
    child_scheme #(.ADDRESS(ADDRESS), .MASK(MASK), .PACKET_WIDTH(PACKET_WIDTH)) c1s(c1_in, c1_c2, c1_p);
    child_scheme #(.ADDRESS(ADDRESS), .MASK(MASK), .PACKET_WIDTH(PACKET_WIDTH)) c2s(c2_in, c2_c1, c2_p);

    arbiter_merge #(.PACKET_WIDTH(PACKET_WIDTH)) am_p(c1_p, c2_p, p_out);
    arbiter_merge #(.PACKET_WIDTH(PACKET_WIDTH)) am_c1(p_c1, c2_c1, c1_out);
    arbiter_merge #(.PACKET_WIDTH(PACKET_WIDTH)) am_c2(p_c2, c1_c2, c2_out);

endmodule

module error_injector (interface out);
    logic s;
    always begin
        s = $random();
        out.Send(s);
    end
endmodule

module top_router (interface c1_in, c2_in, c1_out, c2_out, err_in);
    parameter FL = 4;
    parameter PACKET_WIDTH = 16;
    parameter reg[3:0] ADDRESS = 4'b0000;
    parameter reg[3:0] MASK = 4'b0000;
    logic [PACKET_WIDTH-1:0] packet_c1, packet_c2;
    logic [3:0] error_place;
    logic s;
    // logic c1_req = 0, c2_req = 0;

    always begin
        fork
            c1_in.Receive(packet_c1);
            err_in.Receive(s);
        join
        if (s) begin
            error_place = $urandom_range(15,0);
            packet_c1[error_place] = ~packet_c1[error_place];
        end
        #FL;
        c2_out.Send(packet_c1);
    end

    always begin
        fork
            c2_in.Receive(packet_c2);
            err_in.Receive(s);
        join
        if (s) begin
            error_place = $urandom_range(15,0);
            packet_c2[error_place] = ~packet_c2[error_place];
        end
        #FL;
        c1_out.Send(packet_c2);
    end
endmodule // top_router

// port should act as a data generator and data bucket
module port (interface a_in, a_out, output logic [15:0] sent_num = 0, received_num = 0);
    parameter FL = 8;
    parameter BL = 0;
    parameter reg[3:0] ADDRESS = 4'b0000;
    parameter PACKET_WIDTH = 16;
    parameter ADDRESS_WIDTH = 4;
    parameter DATA_WIDTH = 4;
    logic [PACKET_WIDTH-1:0] sent_packet = 0, received_packet;
    logic [ADDRESS_WIDTH-1:0] dest_address;
    logic [DATA_WIDTH-1:0] packet_data;
    logic [3:0] random_fl;
    logic sent_parity;
    string correctness;

    // initial begin
    //     // send packet from J to A, 1001 to 0000
    //     if (ADDRESS == 4'b1001) begin
    //         sent_packet = 16'b0000100100001111;
    //         #4;
    //         a_out.Send(sent_packet);
    //         sent_num = sent_num + 1;
    //         $display("--------------------------------------------------------------------------------");
    //         $display("(Time: \t\t %t),\t Sending", $time);
    //         $display("Sending pakcet on port \t%b", ADDRESS);
    //         $display("packet: \t%b, data: \t%b, destination: \t%b", sent_packet, sent_packet[3:0], sent_packet[7:4]);
    //     end
    // end
    always begin
        packet_data = $random() % (2**DATA_WIDTH);
        dest_address = $random() % (2**ADDRESS_WIDTH);
        // make sure dest address is not itself
        while (dest_address == ADDRESS) begin
            dest_address = $random() % (2**ADDRESS_WIDTH);
        end
        sent_packet[DATA_WIDTH-1:0] = packet_data;
        sent_packet[7:4] = dest_address;
        sent_packet[11:8] = ADDRESS;
        sent_packet[12] = 0;
        sent_packet[13] = ^sent_packet[12:0];
        random_fl = $random() % (16);
        #random_fl;
        a_out.Send(sent_packet);
		sent_num = sent_num + 1;
        $display("--------------------------------------------------------------------------------");
        $display("(Time: \t\t %t),\t Sending", $time);
        $display("Sending pakcet on port \t%b", ADDRESS);
        $display("packet: \t%b, data: \t%b, destination: \t%b", sent_packet, sent_packet[3:0], sent_packet[7:4]);
    end

    always begin
        a_in.Receive(received_packet);
        #BL;
		received_num = received_num + 1;
        if (received_packet[13] == ^received_packet[12:0])
            correctness = "correct";
        else
            correctness = "incorrect";
        $display("--------------------------------------------------------------------------------");
        $display("(Time: \t\t %t)\t Port Receiving", $time);
        $display("Receiving pakcet on port \t%b", ADDRESS);
        $display("packet: \t%b, data: \t%b, source: \t%b", received_packet, received_packet[3:0], received_packet[11:8]);
        $display("the packet is %s", correctness);
    end


endmodule // port



module tree_noc (output logic [31:0] sent_total_num = 0, received_total_num = 0);
    logic [15:0] sent_nums [15:0];
    logic [15:0] received_nums [15:0];
    integer j;

    Channel #(.WIDTH(16), .hsProtocol(P4PhaseBD)) intf_0_in [15:0] ();
    Channel #(.WIDTH(16), .hsProtocol(P4PhaseBD)) intf_1_in [7:0] ();
    Channel #(.WIDTH(16), .hsProtocol(P4PhaseBD)) intf_2_in [3:0] ();
    Channel #(.WIDTH(16), .hsProtocol(P4PhaseBD)) intf_3_in [1:0] ();

    Channel #(.WIDTH(16), .hsProtocol(P4PhaseBD)) intf_0_out [15:0] ();
    Channel #(.WIDTH(16), .hsProtocol(P4PhaseBD)) intf_1_out [7:0] ();
    Channel #(.WIDTH(16), .hsProtocol(P4PhaseBD)) intf_2_out [3:0] ();
    Channel #(.WIDTH(16), .hsProtocol(P4PhaseBD)) intf_3_out [1:0] ();

    Channel #(.WIDTH(1), .hsProtocol(P4PhaseBD)) error_in ();

    genvar i;
    generate
        for(i = 0; i <= 15; i = i + 1) begin
            port #(.ADDRESS(i)) po(intf_0_in[i], intf_0_out[i], sent_nums[i], received_nums[i]);
        end
        for(i = 0; i <= 7; i = i + 1) begin
            router #(.ADDRESS(i*2), .MASK(4'b1110)) tr(intf_1_in[i], intf_0_out[i*2], intf_0_out[i*2+1], intf_1_out[i], intf_0_in[i*2], intf_0_in[i*2+1]);
        end
        for(i = 0; i <= 3; i = i + 1) begin
            router #(.ADDRESS(i*4), .MASK(4'b1100)) tr(intf_2_in[i], intf_1_out[i*2], intf_1_out[i*2+1], intf_2_out[i], intf_1_in[i*2], intf_1_in[i*2+1]);
        end
        for(i = 0; i <= 1; i = i + 1) begin
            router #(.ADDRESS(i*8), .MASK(4'b1000)) tr(intf_3_in[i], intf_2_out[i*2], intf_2_out[i*2+1], intf_3_out[i], intf_2_in[i*2], intf_2_in[i*2+1]);
        end
        top_router topr(intf_3_out[0], intf_3_out[1], intf_3_in[0], intf_3_in[1], error_in);
        error_injector ein(error_in);
    endgenerate

	always @(*) begin
        sent_total_num = 0;
        received_total_num = 0;
        for (j = 0; j < 16; j = j + 1) begin
            //$display("sent_total_num = %d, current j = %d, current sent_num = %d", sent_total_num, j, sent_nums[j]);
            sent_total_num = sent_total_num + sent_nums[j];
            received_total_num = received_total_num + received_nums[j];
        end
    end
endmodule // tree_noc

module tb_tree_noc ();
logic [31:0] sent_total_num, received_total_num;
tree_noc tn(sent_total_num, received_total_num);
initial begin
    $timeformat(-9, 0, "ns", 5);
    #1000;
	$display("At time = %t, Total number of packets have been sent is %d, Total number of packets have been received is %d", $time, sent_total_num, received_total_num);
    $stop;
end
endmodule // tb_tree_noc
