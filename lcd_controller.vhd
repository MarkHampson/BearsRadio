library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity lcd_controller is

	port(
		clk: in std_logic;
		row1_text: in string (1 to 16);
		row2_text: in string (1 to 16);
		
		backlight: out std_logic;
		--lcd_on: out std_logic;
		lcd_rs: out std_logic;
		lcd_rw: out std_logic;
		lcd_e: out std_logic;
		lcd_data: out std_logic_vector( 7 downto 0)
		);
		
end lcd_controller;

architecture Rayonnant_Gothic of lcd_controller is

--    constant row1_text: string := "What the fucking";
--    constant row2_text: string := "fuck?           ";

	constant function_set : std_logic_vector (7 downto 0) := "00111000";
	constant display_on: std_logic_vector (7 downto 0) := "00001100";
	constant display_clr: std_logic_vector (7 downto 0) := "00000001";
	constant entry_mode_set: std_logic_vector (7 downto 0) := "00000110";	
	--constant return_home: std_logic_vector(7 downto 0) := "00000010";
	
	constant goto_line1 : std_logic_vector(7 downto 0) := "10000000";
    constant goto_line2 : std_logic_vector(7 downto 0) := "11000000";
	
	constant count_15ms: integer := 2**20;
	constant count_1ms: integer := 36864;
	
	type init_string_t is array (0 to 3) of std_logic_vector (7 downto 0);
	signal init_string : init_string_t := 
	(function_set, display_on, display_clr, entry_mode_set);

	type init_state_t is (idle, send_function_set, pre_init_string, send_init_string, init_done);
	signal init_state: init_state_t;
	
	type active_state_t is (idle, scan, pre_write_address, write_address, pre_write_data, write_data);
	signal active_state: active_state_t;
	
	signal counter_15: integer range 0 to count_15ms;
	signal string_counter: integer range 0 to 4;
	signal write_counter: integer range 0 to count_1ms;
	signal init_counter: integer range 0 to 3;
	
	signal stored_text1: string  (1 to 16) := "1234567890123456";
	signal stored_text2: string  (1 to 16) := "1234567890123456";
	signal column: natural range 1 to 16;
	signal row: natural range 1 to 2;
	signal ce: std_logic;
	
	--signal busy_flag: std_logic;
	
begin
	--lcd_on <= '1';  -- turn it on
	backlight <= '1';

--    lcd_e <= '1';
--    lcd_rw <= '1';
--    lcd_rs <= '1';
--    lcd_data <= X"12";
--slow_it_down:
--	process(clk)
--		variable slow_count: integer range 0 to 15;
--	begin
--		if(rising_edge(clk)) then
--			if(slow_count = 0) then
--				ce <= '1';
--			else
--				ce <= '0';
--				slow_count := slow_count + 1;
--			end if;
--		end if;
--	end process;


-- Initialization state machine
init_state_machine:
	process(clk)
	begin
		if(clk'event and clk='1') then
			case init_state is
				when idle =>
					init_state <= send_function_set; -- start counter_15ms
				when send_function_set =>
					if(counter_15 = 0) then
						if(init_counter = 3) then
							init_state <= pre_init_string;
						else 
							init_state <= idle; -- this will reset counter_15ms
							init_counter <= init_counter + 1;
						end if;
					end if;
				when pre_init_string =>
					init_state <= send_init_string; -- start counter_15ms
				when send_init_string =>
					if(counter_15 = 0) then
						if(string_counter = 4) then
							init_state <= init_done;
						else 
							init_state <= pre_init_string; -- reset counter_15ms
							string_counter <= string_counter + 1;
						end if;
					end if;
				when init_done =>
					init_state <= init_done;
			end case;
		end if;
	end process init_state_machine;

-- Normal operation state machine
active_state_machine:
		process(clk)
		begin
			if(clk'event and clk = '1') then
				case active_state is
					when idle =>
						if(init_state /= init_done) then
							active_state <= idle;
						else active_state <= scan;
						end if;
					when scan =>
						if(row = 1) then
							if(stored_text1(column)=row1_text(column)) then
							-- no need to update
								if(column = 16) then
									column <= 1;
									row <= 2;
								else column <= column + 1;
								end if;
							else -- mismatch => need to update
								-- set address first
								stored_text1(column) <= row1_text(column);
								active_state <= pre_write_address;
							end if;
						end if;
						if(row = 2) then
							if(stored_text2(column)=row2_text(column)) then
								if(column = 16) then
									column <= 1;
									row <= 1;
								else column <= column + 1;
								end if;
							else
								stored_text2(column) <= row2_text(column);
								active_state <= pre_write_address;
							end if;
						end if;
					when pre_write_address =>
						active_state <= write_address;
					when write_address =>
						if( write_counter = 0) then
							active_state <= pre_write_data;
						end if;
					when pre_write_data =>
						active_state <= write_data;
					when write_data =>
						if( write_counter = 0) then
							active_state <= scan;
						end if;
				end case;
			end if;
		end process active_state_machine;

-- Signal behavior		
counter_15ms:
	process(clk)
	begin
		if(clk'event and clk='1') then
			if(init_state = idle or
			   init_state = pre_init_string) then
				counter_15 <= count_15ms;
			elsif(counter_15 > 0) then
				counter_15 <= counter_15 - 1;
			end if;
		end if;
	end process counter_15ms;
	
write_counter_process:
	process(clk)
	begin
		if(clk'event and clk = '1') then
			if(active_state = pre_write_address or
			   active_state = pre_write_data) then
				write_counter <= count_1ms;
			elsif( write_counter > 0) then
				write_counter <= write_counter - 1;
			end if;
		end if;
	end process;

lcd_rs_rw_control:
	process(clk)
	begin
		if(clk'event and clk = '1') then
			if(active_state = write_data) then
				lcd_rw <= '0';
				lcd_rs <= '1';
			else
				lcd_rw <= '0';
				lcd_rs <= '0';
			end if;
		end if;
	end process lcd_rs_rw_control;
				
lcd_e_control:
	process(clk)
	begin
		if(clk'event and clk = '1') then
			if(init_state = send_function_set or
			   init_state = send_init_string) then
				if(counter_15 < count_15ms - 8 and
				   counter_15 > count_15ms - 128) then
					lcd_e <= '1';
			    else lcd_e <= '0';
				end if;
			elsif(active_state = write_address or 
			      active_state = write_data) then
				if(write_counter < count_1ms - 8 and
				   write_counter > count_1ms - 128) then
					lcd_e <= '1';
				else lcd_e <= '0';
				end if;
			else lcd_e <= '0';  -- all other states don't write anything
			end if;
		end if;
	end process lcd_e_control;

lcd_data_control:
	process(clk)
	begin
		if(clk'event and clk = '1') then
			if((init_state = idle) or
			   (init_state = pre_init_string) or
			   (active_state = scan) or 
				(active_state = pre_write_address) or 
				(active_state = pre_write_data) or
			   ((init_state = init_done) and (active_state = idle))) then
				lcd_data <= (others => '0');
			end if;
			if(init_state = send_function_set) then
				if(init_counter = 3) then
					lcd_data <= (others => '0');
				else
					lcd_data <= function_set;
				end if;
			end if;
			if(init_state = send_init_string) then
				if(string_counter = 4) then
					lcd_data <= (others => '0');
				else
					lcd_data <= init_string(string_counter);
				end if;
			end if;
			if(active_state = write_address) then
				if( row = 1 ) then
					lcd_data <= goto_line1 or std_logic_vector(to_unsigned(column-1, 8));
				else
					lcd_data <= goto_line2 or std_logic_vector(to_unsigned(column-1, 8));
				end if;
			end if;
			if(active_state = write_data) then
				if( row = 1 ) then
					lcd_data <= std_logic_vector(to_unsigned(character'pos(stored_text1(column)),8));
				else
					lcd_data <= std_logic_vector(to_unsigned(character'pos(stored_text2(column)),8));
				end if;
			end if;
		end if;
	end process lcd_data_control;

end Rayonnant_Gothic;













