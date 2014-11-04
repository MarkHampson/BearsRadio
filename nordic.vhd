library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.spi_config;
use work.spi_read_payload;


entity nordic is
	port(
		clk: in std_logic;
		irq: in std_logic;
		mosi: out std_logic;
		miso: in std_logic;
		sck: out std_logic;
		csn: out std_logic;
		ce: out std_logic;
		
		payload_ready: buffer std_logic;
		button: buffer std_logic_vector(15 downto 0)
	
		);
end nordic;

architecture Dragestil of nordic is
		
	signal spi_ce: std_logic;
	signal configured: std_logic;
	
	type packet_state_t is (waiting_for_packet, packet_received, get_data, reset_irq, lockout);
	signal packet_state: packet_state_t;
	
	signal status: std_logic_vector(7 downto 0);
	signal presses: std_logic_vector(15 downto 0);
	
	signal read_new_data: std_logic;
	
	signal mosi1,mosi2,sck1,sck2,csn1,csn2: std_logic;
	
begin

spi_timing: process(clk)
		variable clk_divide: integer range 0 to 7; -- 36.864 MHz/8 = 4.608 MHz
	begin
		if(clk'event and clk = '1') then
			if(clk_divide = 7) then
				clk_divide := 0;
				spi_ce <= '1';
			else
				clk_divide := clk_divide + 1;
				spi_ce <= '0';
			end if;
		end if;
	end process;

with configured select
		mosi <= mosi1 when '0',
				mosi2 when others;
with configured select
		sck  <= sck1 when '0',
				sck2 when others;
with configured select
		csn  <= csn1 when '0',
				csn2 when others;
	
configure_receiver: entity spi_config port map(
		clk => clk,
		spi_ce => spi_ce,
		mosi => mosi1,
		sck => sck1,
		csn => csn1,
		done => configured
		);

read_payload: entity spi_read_payload port map(
		clk => clk,
		spi_ce => spi_ce,
		read_new_data => read_new_data,
		mosi => mosi2,
		miso => miso,
		sck => sck2,
		payload_ready => payload_ready,
		csn => csn2,
		status => status,
		button_press_data => button,
		press_history_data => presses
		);
		
wait_for_interrupt: process(clk, spi_ce)
                constant lockout_counter_high: integer := 32768*20;
				variable lockout_counter: integer range 0 to lockout_counter_high; -- 10 ms
			begin
			if(clk'event and clk = '1' and spi_ce = '1') then
				case packet_state is
					when waiting_for_packet =>
						if( configured = '1' ) then
							ce <= '1';
						else ce <= '0';
						end if;
						
						if( irq = '0' ) then
							packet_state <= packet_received;
							ce <= '0';  -- go to standby mode
						end if;
					when packet_received =>
						read_new_data <= '1';  -- signal spi transfer
						packet_state <= get_data;
					when get_data => 
						if( payload_ready = '1' ) then
							read_new_data <= '0'; -- this is the ACK to the SPI unit
							packet_state <= reset_irq;
						end if;
					when reset_irq =>
						if( irq = '1' ) then
							packet_state <= lockout;
						end if;
					when lockout =>
						if( lockout_counter = lockout_counter_high ) then
							lockout_counter := 0;
							packet_state <= waiting_for_packet;
						else
							lockout_counter := lockout_counter + 1;
						end if;
				end case;
			end if;
		end process;
	
end Dragestil;
		