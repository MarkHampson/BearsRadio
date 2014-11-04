library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity i2c_comm is
	port(
		clk: in std_logic;
		sda: inout std_logic;
		scl: out std_logic;
		ack: out std_logic;
		--bit_counter: out integer range 0 to 8;
		done: out std_logic
		);
end i2c_comm;

architecture Merovingian of i2c_comm is

	type state_t is (idle, start, send, stop);
	signal state: state_t;
	
	constant codec_address: std_logic_vector(8 downto 0) := X"34" & 'Z';
	
	constant power_down_ctl_addr: std_logic_vector(8 downto 0) := "0000110" & '0' & 'Z';
	constant power_down_ctl_data: std_logic_vector(8 downto 0) := "01100010" & 'Z';
	constant left_line_in_addr: std_logic_vector(8 downto 0) :=   "0000000" & '0' & 'Z';
	constant left_line_in_data: std_logic_vector(8 downto 0) :=   "00010111" & 'Z'; -- 0 dB
	constant right_line_in_addr: std_logic_vector(8 downto 0) :=  "0000001" & '0' & 'Z';
	constant right_line_in_data: std_logic_vector(8 downto 0) :=  "00010111" & 'Z'; -- 0 dB
	constant analog_path_addr: std_logic_vector(8 downto 0) :=    "0000100" & '0' & 'Z';
	constant analog_path_data: std_logic_vector(8 downto 0) :=    "00010010" & 'Z';
	constant active_ctl_addr: std_logic_vector(8 downto 0) :=     "0001001" & '0' & 'Z';
	constant active_ctl_data: std_logic_vector(8 downto 0) :=     "00000001" & 'Z';
	constant left_out_addr: std_logic_vector(8 downto 0) := 	  "0000010" & '0' & 'Z';
	constant left_out_data: std_logic_vector(8 downto 0) :=	 	  "01100001" & 'Z'; -- -24 dB (less hiss)
	constant right_out_addr: std_logic_vector(8 downto 0) := 	  "0000011" & '0' & 'Z';
	constant right_out_data: std_logic_vector(8 downto 0) :=      "01100001" & 'Z'; -- -24 dB
	constant digital_path_addr: std_logic_vector(8 downto 0) :=   "0000101" & '0' & 'Z';
	constant digital_path_data: std_logic_vector(8 downto 0) :=   "00000000" & 'Z';
	constant digital_format_addr: std_logic_vector(8 downto 0) := "0000111" & '0' & 'Z';
	constant digital_format_data: std_logic_vector(8 downto 0) := "00000010" & 'Z';
	
	type transmit_bytes_t is array (0 to 2) of std_logic_vector(8 downto 0);
	
	constant power_down: transmit_bytes_t := (codec_address, power_down_ctl_addr, power_down_ctl_data);
	constant left_in: transmit_bytes_t := (codec_address, left_line_in_addr, left_line_in_data);
	constant right_in: transmit_bytes_t := (codec_address, right_line_in_addr, right_line_in_data);
	constant analog_path: transmit_bytes_t := (codec_address, analog_path_addr, analog_path_data);
	constant active_ctl: transmit_bytes_t := (codec_address, active_ctl_addr, active_ctl_data);
	constant left_out: transmit_bytes_t := (codec_address, left_out_addr, left_out_data);
	constant right_out: transmit_bytes_t := (codec_address, right_out_addr, right_out_data);
	constant digital_path: transmit_bytes_t := (codec_address, digital_path_addr, digital_path_data);
	constant digital_format: transmit_bytes_t := (codec_address, digital_format_addr, digital_format_data);
	
	type register_sequence_t is array (0 to 8) of transmit_bytes_t;
	constant register_sequence: register_sequence_t := 
		 ( power_down, left_in, left_out, right_in , right_out, digital_path, analog_path, active_ctl, digital_format);
	
begin

	process(clk)
		variable clk_div: integer range 0 to 739; -- 99 kHz I2C clk @ 369
		variable bit_count: integer range 0 to 8; -- 8 bits, 1 ack
		variable byte_count: integer range 0 to 2;
		variable reg_count: integer range 0 to register_sequence'high;
	begin
		if(clk'event and clk = '1') then
			case state is
				when idle =>
					sda <= '1';
					scl <= '1';
					done <= '0';
					state <= start;
				
				when start =>
					if(clk_div = 369) then
						scl <= '0';
						sda <= register_sequence(reg_count)(byte_count)(8-bit_count);
						state <= send;
						clk_div := 0; -- restart clk divider
					elsif(clk_div = 184) then
						sda <= '0';
						clk_div := clk_div + 1;
					else
						clk_div := clk_div + 1;
					end if;
					
				when send =>
					--bit_counter <= bit_count; 
					if(clk_div = 369) then
						clk_div := 0;
						scl <= '0';
						if(bit_count = 8) then
							-- start a new byte, or end transmission
							if(byte_count = 2) then -- done with final ack
								state <= stop;
								sda <= '0';
								byte_count := 0;
								bit_count := 0;
							else  -- new byte
								byte_count := byte_count + 1; 
								bit_count := 0;
								sda <= register_sequence(reg_count)(byte_count)(8-bit_count); -- first bit of new byte
							end if;
						else -- still working on the current byte
							bit_count := bit_count + 1;
							sda <= register_sequence(reg_count)(byte_count)(8-bit_count);
						end if;
					elsif(clk_div = 184) then
						scl <= '1';
						clk_div := clk_div + 1;
						if(bit_count = 8) then
							ack <= not sda; -- watch for acknowledge;
						end if;
					else
						clk_div := clk_div + 1;
					end if;
				
				when stop =>
					if(clk_div = 739) then
						if(reg_count = register_sequence'high) then
							done <= '1';
						else
							reg_count := reg_count + 1;
							clk_div := 0;
							state <= idle;
						end if;
					elsif(clk_div = 369) then
						sda <= '1';
						clk_div := clk_div + 1;
					elsif(clk_div = 184) then
						scl <= '1';
						clk_div := clk_div + 1;
					else
						clk_div := clk_div + 1;
					end if;
				end case;
			end if;
		end process;
end Merovingian;
	
	
	
	
	