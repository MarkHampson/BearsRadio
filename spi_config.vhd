library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity spi_config is
	port(
		clk: in std_logic;
		spi_ce: in std_logic;
		mosi: out std_logic;
		csn: out std_logic;
		sck: buffer std_logic;
		done: out std_logic
		);
end spi_config;

architecture Markov of spi_config is

	type config_state_t is (init, send_config_data, config_complete);
	signal config_state: config_state_t;
	
	type spi_state_t is (idle, start, transmitting, stop);
	signal spi_state: spi_state_t;
	
	type config_regs_t is array (0 to 6) of std_logic_vector(15 downto 0);
	constant config_regs: config_regs_t :=
				( X"2039",
				  X"2100",
				  X"2303",
				  X"2607",
				  X"3104",
				  X"2502",
				  X"203B"
				  );
	
begin

	process(clk, spi_ce)
		variable config_count: integer range 0 to 6;
		variable bit_count: integer range 0 to 15;
		variable clock_low: boolean;
	begin
		if(clk'event and clk = '1' and spi_ce = '1') then
			case config_state is
				when init =>
					clock_low := true;
					csn <= '1';
					mosi <= '0';
					sck <= '0';
					done <= '0';
					config_state <= send_config_data;
				when send_config_data =>
					case spi_state is
						when idle =>
							spi_state <= start;
						when start =>
							csn <= '0'; -- drop the SPI latch enable
							spi_state <= transmitting;
						when transmitting =>
							if( clock_low ) then
								sck <= '0';
								mosi <= config_regs(config_count)(15-bit_count); --MSB first
								clock_low := false;
							else
								sck <= '1';
								clock_low := true;
								if( bit_count = 15 ) then 
									spi_state <= stop;
									bit_count := 0;
								else
									bit_count := bit_count + 1;
								end if;
							end if;
						when stop =>
							sck <= '0';
							csn <= '1'; -- raise the SPI latch enable
							if( config_count = 6 ) then
								config_state <= config_complete;
							else
								config_count := config_count + 1;
								spi_state <= idle;
							end if;
					end case;
				when config_complete =>					
					done <= '1';
			end case;
		end if;
	end process;


end Markov;