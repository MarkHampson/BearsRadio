library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity i2s_comm is
	port(
		clk: in std_logic;
		enable: in std_logic;
		bclk: out std_logic;
		tx_data: out std_logic;
		tx_lrclk: out std_logic;
		rx_data: in std_logic;
		rx_lrclk: out std_logic;
		data_to_send: in std_logic_vector(47 downto 0); --left/right packed 24 bits
		data_received: out std_logic_vector(47 downto 0)
	);
end i2s_comm;

architecture Neoclassical of i2s_comm is

	type i2s_state_t is (idle, left_word, right_word);
	signal i2s_state : i2s_state_t;

begin


	process(clk, enable)
		variable bclk_counter: integer range 0 to 12;
		variable bit_counter: integer range 0 to 32;
		variable transmit_buffer: std_logic_vector(47 downto 0);
		variable receive_buffer: std_logic_vector(47 downto 0);
	begin
		if(clk'event and clk='1' and enable = '1') then
			case i2s_state is
				when idle =>
					bclk <= '0';
					tx_data <= '0';
					tx_lrclk <= '0';
					rx_lrclk <= '0';
					data_received <= (others => '0');
					i2s_state <= left_word;
				when left_word =>
					
					tx_lrclk <= '0';
					rx_lrclk <= '0';
					
					-- bit clock
					if(bclk_counter < 6) then
						bclk <= '0';
						bclk_counter := bclk_counter + 1;
					elsif(bclk_counter = 6) then -- rising edge of bclk, get data
						bclk <= '1';
						bclk_counter := bclk_counter + 1;
						-- rx data bit
						if(bit_counter > 0 and
							bit_counter < 25) then
							receive_buffer(48-bit_counter) := rx_data;
						end if;
					elsif(bclk_counter > 6 and
							bclk_counter < 12) then
						bclk <= '1';
						bclk_counter := bclk_counter + 1;
					else -- bclk_counter = 12
						bclk <= '0';
						bclk_counter := 1;
						if(bit_counter = 31) then
							i2s_state <= right_word;
							bit_counter := 0;
							tx_lrclk <= '1';
							rx_lrclk <= '1';
						else bit_counter := bit_counter + 1;
						
							-- tx data bit
							if(bit_counter > 0 and
							   bit_counter < 25) then
								tx_data <= transmit_buffer(48-bit_counter);
							else tx_data <= '0';
							end if;
						
						end if;
					end if;
					
					--bit_count <= bit_counter;
					
				when right_word =>
					
					tx_lrclk <= '1';
					rx_lrclk <= '1';
					
					-- bit clock
					if(bclk_counter < 6) then
						bclk <= '0';
						bclk_counter := bclk_counter + 1;
					elsif(bclk_counter = 6) then
						bclk <= '1';
						bclk_counter := bclk_counter + 1;
						-- rx data bit
						if(bit_counter > 0 and
							bit_counter < 25) then
								receive_buffer(24-bit_counter) := rx_data;
						end if;
					elsif(bclk_counter > 6 and
							bclk_counter < 12) then
						bclk <= '1';
						bclk_counter := bclk_counter + 1;
					else -- bclk_counter = 4
						bclk <= '0';
						bclk_counter := 1;
						if(bit_counter = 31) then
							i2s_state <= left_word;
							bit_counter := 0;
							tx_lrclk <= '0';
							rx_lrclk <= '0';
							transmit_buffer := data_to_send; -- latch outgoing data
							data_received <= receive_buffer; -- latch received data
						else bit_counter := bit_counter + 1;
						
							-- tx data bit
							if(bit_counter > 0 and
							   bit_counter < 25) then
								tx_data <= transmit_buffer(24-bit_counter);
							else tx_data <= '0';
							end if;
							
						end if;
					end if;
					
					--bit_count <= bit_counter;
					
				end case;
			end if;		
	end process;

end Neoclassical;




