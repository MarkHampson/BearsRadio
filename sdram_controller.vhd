library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sdram_controller is

	port(
	
		clk: in std_logic; -- master clock
		
		-- SDRAM control pins
		sdram_clk: out std_logic;
		cke: out std_logic; -- clock enable
		n_cs: buffer std_logic; -- chip select
		n_ras: buffer std_logic; -- row address strobe
		n_cas: buffer std_logic; -- column address strobe
		n_we: buffer std_logic; -- write enable
		dq: inout std_logic_vector(15 downto 0);
		dqm: out std_logic; -- DQ mask enable
		ldqm: out std_logic;
		addr: buffer std_logic_vector(11 downto 0);
		ba: out std_logic_vector(1 downto 0);
		
		-- User interface
		--test: out boolean;
		data_received: out std_logic_vector(15 downto 0);
		send_this_data: in std_logic_vector(15 downto 0);
		address: in std_logic_vector(21 downto 0);  -- user address space
		enable: in boolean;
		ack: out boolean;
		read_data_valid: out boolean;
		read_nwrite: in boolean
		
	);
end sdram_controller;

architecture Mordor of sdram_controller is


type sdram_state_t is ( -- initialization states
						wait_200, 
						init_precharge,
						init_refresh, 
						init_mode,
						-- normal operation states
						idle,
						auto_refresh,
						precharge,
						--read_data,
						--write_data,
						read_auto_precharge,
						write_auto_precharge,
						row_active
						--active_power_down
						);
						
signal sdram_state: sdram_state_t;

type command_t is (
					--desl,
					nop,
					mrs,
					act,
					--read_cmd,
					read_auto,
					--write_cmd,
					write_auto,
					nop_writing,
					--pre,
					pall,
					--bst,
					ref
					--self
					);

signal command: command_t;

signal bank_address: std_logic_vector(1 downto 0);
signal row_address: std_logic_vector(11 downto 0);
signal column_address: std_logic_vector(7 downto 0);

constant CAS_latency: integer := 2;
constant burst_length: integer := 2;
					
begin

sdram_clk <= clk;
ldqm <= '0'; -- no byte masking

command_outputs:
	process(command, bank_address, row_address, column_address, send_this_data)
	begin
		case command is
			when nop =>
				n_cs <= '0';
				n_ras <= '1';
				n_cas <= '1';
				n_we <= '1';
				ba <= (others => 'X');
				addr <= (others => 'X');
				dq <= (others => 'Z');
			when pall =>
				n_cs <= '0';
				n_ras <= '0';
				n_cas <= '1';
				n_we <= '0';
				addr(10) <= '1';
				ba <= (others => 'X');
				addr(11) <= 'X';
				addr(9 downto 0) <= (others => 'X');
				dq <= (others => 'Z');
			when ref =>
				n_cs <= '0';
				n_ras <= '0';
				n_cas <= '0';
				n_we <= '1';
				ba <= (others => 'X');
				addr <= (others => 'X');
				dq <= (others => 'Z');
			when mrs =>
				n_cs <= '0';
				n_ras <= '0';
				n_cas <= '0';
				n_we <= '0';
				ba <= (others => '0');
				addr(11 downto 7) <= (others => '0'); -- burst read and burst write
				addr(6 downto 4) <= "010";  -- CAS latency = 2
				addr(3) <= '0';  -- sequential write
				addr(2 downto 0) <= "001";  -- double word burst length
				dq <= (others => 'Z');
			when act =>
				n_cs <= '0';
				n_ras <= '0';
				n_cas <= '1';
				n_we <= '1';
				ba <= bank_address;
				addr(11 downto 0) <= row_address;
				dq <= (others => 'Z');
			when read_auto =>
				n_cs <= '0';
				n_ras <= '1';
				n_cas <= '0';
				n_we <= '1';
				ba <= bank_address;
				addr(10) <= '1'; -- auto precharge
				addr(7 downto 0) <= column_address;
				addr(11) <= 'X';
				addr(9 downto 8) <= (others => 'X');
				dq <= (others => 'Z');
			when write_auto =>
				n_cs <= '0';
				n_ras <= '1';
				n_cas <= '0';
				n_we <= '0';
				ba <= bank_address;
				addr(10) <= '1';  --auto precharge
				addr(7 downto 0) <= column_address;
				addr(11) <= 'X';
				addr(9 downto 8) <= (others => 'X');
				dq <= send_this_data;
			when nop_writing =>
				n_cs <= '0';
				n_ras <= '1';
				n_cas <= '1';
				n_we <= '1';
				ba <= (others => 'X');
				addr <= (others => 'X');
				dq <= send_this_data;
		end case;
	end process command_outputs;
				
			
sdram_state_machine:
	process(clk)
		variable wait_200_counter: integer range 0 to 20000; -- 200us --> 20,000 clocks at 100 MHz
		variable init_refresh_count: integer range 0 to 7;
		variable tRP_counter: integer range 0 to 1; -- 20 ns --> two clocks at 100 MHz
		variable tRC_counter: integer range 0 to 6; -- 70 ns --> seven clocks at 100 MHz
		variable current_address: std_logic_vector(21 downto 0);
		variable current_bank: std_logic_vector(1 downto 0);
		variable current_row: std_logic_vector(11 downto 0);
		variable current_column: std_logic_vector(7 downto 0);
		variable read_nwrite_cmd: boolean;
		variable CAS_counter: integer range 0 to CAS_latency;
		variable burst_counter: integer range 0 to burst_length-1;
	begin
		if(clk'event and clk = '0') then
			case sdram_state is
				when wait_200 => 
					dqm <= '1';
					cke <= '1';
					command <= nop;
					if(wait_200_counter = 20000) then --20000 when live
						sdram_state <= init_precharge;
						command <= pall;
					else
						wait_200_counter := wait_200_counter + 1;
					end if;
				when init_precharge =>
					if(tRP_counter = 1) then
						tRP_counter := 0;  -- reset counter
						sdram_state <= init_refresh;
						command <= ref;
					else
						command <= nop;
						tRP_counter := tRP_counter + 1;
					end if;
				when init_refresh =>
					if(tRC_counter = 6) then
						tRC_counter := 0; -- reset counter in either case
						if(init_refresh_count = 7) then -- done refreshing
							sdram_state <= init_mode; -- go to next state
							command <= mrs;       -- issue mode register setting command
						else
							command <= ref; -- issue another refresh command
							init_refresh_count := init_refresh_count + 1;
						end if;
					else
						tRC_counter := tRC_counter + 1;
						command <= nop;
					end if;
				when init_mode =>
					if(tRP_counter = 1) then
						tRP_counter := 0;
						sdram_state <= idle;
						dqm <= '0';
					else
						tRP_counter := tRP_counter + 1;
						command <= nop;
					end if;
				when idle =>
					read_data_valid <= false;
					if(enable) then
						read_nwrite_cmd := read_nwrite;
						current_address := address;
						current_bank := address(21 downto 20);
						current_row := address(19 downto 8);
						current_column := address(7 downto 0);
						bank_address <= current_bank;
						row_address <= current_row;
						column_address <= current_column;
						sdram_state <= row_active;
						command <= act;
						ack <= true;
					else -- do self-refresh or auto_refresh loop
						command <= ref;
						sdram_state <= auto_refresh;
					end if;
				when row_active =>
					if(CAS_counter = CAS_latency-1) then
						ack <= false;
						CAS_counter := 0; --reset counter
						if(read_nwrite_cmd) then
							sdram_state <= read_auto_precharge;
							command <= read_auto;
						else
							sdram_state <= write_auto_precharge;
							command <= write_auto;
							burst_counter := burst_counter + 1;  -- write begins immediately
						end if;
					else
						CAS_counter := CAS_counter + 1;
						command <= nop;
					end if;
				when read_auto_precharge =>
					if(CAS_counter = CAS_latency-1) then
						data_received <= dq;
						read_data_valid <= true;
						if(burst_counter = burst_length-1) then
							
							burst_counter := 0;
							CAS_counter := 0;
							sdram_state <= auto_refresh;
						else burst_counter := burst_counter + 1;
							
						end if;
					else
						 read_data_valid <= false;
						 CAS_counter := CAS_counter + 1;
						 command <= nop;
					end if;
				when write_auto_precharge =>
					if(burst_counter = burst_length-1) then
						command <= nop_writing;
						burst_counter := 0;
						sdram_state <= precharge;
					else burst_counter := burst_counter + 1;
						command <= nop_writing;
					end if;
				when precharge =>
					command <= nop;
					if(tRP_counter = 1) then
						sdram_state <= auto_refresh;
						tRP_counter := 0;
					else tRP_counter := tRP_counter + 1;
					end if;
				when auto_refresh =>
					if(tRC_counter = 6) then
						tRC_counter := 0; -- reset counter
						if(enable) then
							sdram_state <= idle; -- watch for user input
						else
							command <= ref;  -- keep refreshing
						end if;
					else
						tRC_counter := tRC_counter + 1;
						command <= nop;
					end if;
			end case;
		end if;
	end process sdram_state_machine;
					

end Mordor;








