library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity spi_read_payload is
	port(
		clk: in std_logic;
		spi_ce: in std_logic;
		read_new_data: in std_logic;
		mosi: out std_logic;
		miso: in std_logic;
		csn: out std_logic;
		sck: buffer std_logic;
		payload_ready: out std_logic;
		status: out std_logic_vector(7 downto 0);
		button_press_data: out std_logic_vector(15 downto 0);
		press_history_data: out std_logic_vector(15 downto 0)
		);
end spi_read_payload;

architecture Markov of spi_read_payload is
	
	type spi_state_t is (idle, start, duplex_transmission , stop, waiting_for_ack, flush, clear_interrupt);
	signal spi_state: spi_state_t;
	
	type receive_register_t is array (0 to 4) of std_logic_vector(7 downto 0);
	
	constant read_payload: std_logic_vector(7 downto 0) := X"61";
	constant flush_rx: std_logic_vector(7 downto 0) := X"E2";
	
	type clear_interrupt_t is array (0 to 1) of std_logic_vector(7 downto 0);
	constant clear_interrupt_reg: clear_interrupt_t := (X"27", X"40");
	
begin

	process(clk, spi_ce)
		variable byte_count: integer range 0 to 4;
		variable bit_count: integer range 0 to 7;
		variable clock_low: boolean;
		variable clearing_interrupt: boolean;
		variable flushing: boolean;
		variable receive_register: receive_register_t;
	begin
		if(clk'event and clk = '1' and spi_ce = '1') then
					case spi_state is
						when idle =>
							clock_low := true;
							clearing_interrupt := false;
							csn <= '1';
							mosi <= '0';
							sck <= '0';
							payload_ready <= '0';
							if( read_new_data = '1') then
								spi_state <= start;
							end if;
						when start =>
							csn <= '0'; -- drop the SPI latch enable
							spi_state <= duplex_transmission;
						when duplex_transmission =>
							if( clock_low ) then
								sck <= '0';
								if( flushing ) then
									mosi <= flush_rx(7 - bit_count);
								elsif( clearing_interrupt ) then
									mosi <= clear_interrupt_reg(byte_count)(7-bit_count);
								elsif ( byte_count = 0 ) then
									mosi <= read_payload(7-bit_count); --MSB first
								end if;
								clock_low := false;
							else
								sck <= '1';
								clock_low := true;
								receive_register(byte_count)(7-bit_count) := miso;
								if( bit_count = 7 ) then
									if( flushing ) then -- only one byte, we are done
										spi_state <= stop;
										bit_count := 0;
									elsif(clearing_interrupt) then
										if(byte_count = 1) then -- interrupt cleared
											spi_state <= stop;
											byte_count := 0; -- reset byte count
											bit_count := 0; -- reset bit count
										else
											bit_count := 0;
											byte_count := byte_count + 1;
										end if;
									elsif( byte_count = 4 ) then -- transaction complete
										spi_state <= stop;
										byte_count := 0; -- reset byte count
										bit_count := 0; -- reset bit_count
									else
										bit_count := 0; -- reset the bit count
										byte_count := byte_count + 1; -- go to the next byte
									end if;
								else
									bit_count := bit_count + 1;
								end if;
							end if;
						when stop =>
							sck <= '0';
							csn <= '1'; -- raise the SPI latch enable
							if( flushing ) then
								flushing := false;
								spi_state <= clear_interrupt;
							elsif( clearing_interrupt ) then
								spi_state <= idle;
							else
								payload_ready <= '1';
								status <= receive_register(0);
								button_press_data <= receive_register(0) & receive_register(1);
								press_history_data <= receive_register(2) & receive_register(3);
								spi_state <= waiting_for_ack;
							end if;
						when waiting_for_ack =>
							if( read_new_data = '0' ) then
								payload_ready <= '0';
								spi_state <= flush;
							end if;
						when flush =>
							flushing := true;
							spi_state <= start;
							
						when clear_interrupt =>
							clearing_interrupt := true;
							byte_count := 0;
							spi_state <= start;
							
					end case;
		end if;
	end process;


end Markov;