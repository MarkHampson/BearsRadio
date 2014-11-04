library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity audio_manager is
	port(
		clk: in std_logic;
		test: buffer boolean;
		-- user interface
		increase_delay: in std_logic;
		decrease_delay: in std_logic;
		increment_ack: out std_logic;
		address_increment: in std_logic_vector(16 downto 0);
		delay_string: out string(1 to 16);
		-- interface to I2S module
		lrclk: in std_logic;
		i2s_data_received: in std_logic_vector(47 downto 0);
		i2s_data_send: out std_logic_vector(47 downto 0);
		-- interface to SDRAM controller module
		write_to_ram: out std_logic_vector(15 downto 0);
		read_from_ram: in std_logic_vector(15 downto 0);
		ram_address: out std_logic_vector(21 downto 0);
		ram_enable: out boolean;
		ack: in boolean;
		mute: in std_logic;
		read_nwrite: buffer boolean
	);
end audio_manager;

architecture Muy_Bueno of audio_manager is

	type audio_state_t is (start, input_scan, idle, write_cmd, wait_for_ack, write_data, delay, read_cmd, cas_delay, read_data);
	signal audio_state: audio_state_t;
	
	type calc_delay_state_t is (init, calc_tens, calc_ones, calc_tenths, calc_hundredths, calc_thousandths);
	signal calc_delay_state: calc_delay_state_t;
	
	constant sample_stride: integer := 2; -- left and right channel
	constant sample_rate: integer := 48000;
	constant ten_seconds: integer := sample_rate * 10;
	constant one_second: integer := sample_rate;
	constant one_tenth: integer := sample_rate/10;
	constant one_hundredth: integer := sample_rate/100;
	constant one_thousandth: integer := sample_rate/1000;
	constant delay_1sec: integer := sample_rate * sample_stride;
	constant delay_100ms: integer := delay_1sec/10;
	constant delay_25ms: integer := delay_100ms/4;
	constant delay_10ms: integer := delay_100ms/10;
	constant delay_1ms: integer := delay_10ms/10;
	constant num_words16: integer := 2**22; -- number of 16 bit words in SDRAM
	
	signal lrclk_history : std_logic_vector(1 downto 0);
	signal lrclk_trigger : boolean;
	constant read_address_high: integer := 2**22;
	signal read_address: integer range 0 to 2**22;
	constant write_address_high: integer := 2**22;
	signal write_address: integer range 0 to 2**22;
	signal mode_state: integer range 0 to 3;
	signal sample_delay: integer range 0 to num_words16;

	signal increment: integer range 0 to delay_1sec;
	
	type delay_mode_t is array (0 to 3) of integer range 0 to delay_1sec;
begin

	increment <= to_integer(unsigned(address_increment));

calc_delay_samples: process(clk)
	variable temp: integer range 0 to num_words16;
begin
	if(clk'event and clk='0') then
		if(read_address < write_address) then
			temp := write_address - read_address;
		else
			temp := read_address - write_address;
			temp := num_words16 - temp;
		end if;
		temp := temp / 2; -- number of samples delayed
		sample_delay <= temp;
	end if;
end process;

calc_delay_time: process(clk)
		variable remainder: integer range -num_words16 to num_words16;
		variable digit: integer range 0 to 9;
	begin
		if(clk'event and clk='0') then
			case calc_delay_state is
				when init =>
					remainder := sample_delay;
					calc_delay_state <= calc_tens;
					digit := 0;
					delay_string(3) <= '.';
					delay_string(7 to 16) <= " seconds  ";
				when calc_tens =>
					remainder := remainder - ten_seconds;
					if( remainder < 0 ) then -- done with tens
						remainder := remainder + ten_seconds;
						calc_delay_state <= calc_ones;
						delay_string(1) <= character'val(character'pos('0') + digit);
						digit := 0;  -- reset digit
					elsif( remainder = 0 ) then -- done with tens
						calc_delay_state <= calc_ones;
						delay_string(1) <= character'val(character'pos('0') + digit + 1);
						digit := 0; -- reset digit
					elsif( remainder > 0 ) then
						digit := digit + 1;
					end if;
				when calc_ones =>
					remainder := remainder - one_second;
					if( remainder < 0 ) then -- done with ones
						remainder := remainder + one_second;
						calc_delay_state <= calc_tenths;
						delay_string(2) <= character'val(character'pos('0') + digit);
						digit := 0; -- reset digit
					elsif( remainder = 0 ) then -- done with ones
						calc_delay_state <= calc_tenths;
						delay_string(2) <= character'val(character'pos('0') + digit + 1);
						digit := 0; -- reset digit
					elsif( remainder > 0 ) then
						digit := digit + 1;
					end if;
				when calc_tenths =>
					remainder := remainder - one_tenth;
					if( remainder < 0 ) then -- done with tenths
						remainder := remainder + one_tenth;
						calc_delay_state <= calc_hundredths;
						delay_string(4) <= character'val(character'pos('0') + digit);
						digit := 0; -- reset digit
					elsif( remainder = 0 ) then -- done with tenths
						calc_delay_state <= calc_hundredths;
						delay_string(4) <= character'val(character'pos('0') + digit + 1);
						digit := 0; -- reset digit
					elsif( remainder > 0 ) then
						digit := digit + 1;
					end if;
				when calc_hundredths =>
					remainder := remainder - one_hundredth;
					if( remainder < 0 ) then -- done with hundredths
						remainder := remainder + one_hundredth;
						calc_delay_state <= calc_thousandths;
						delay_string(5) <= character'val(character'pos('0') + digit);
						digit := 0; -- reset digit
					elsif( remainder = 0 ) then -- done with hundredths
						calc_delay_state <= calc_thousandths;
						delay_string(5) <= character'val(character'pos('0') + digit + 1);
						digit := 0; -- reset digit
					elsif( remainder > 0 ) then
						digit := digit + 1;
					end if;
				when calc_thousandths =>
					remainder := remainder - one_thousandth;
					if( remainder < 0 ) then -- done with thousandths
						remainder := remainder + one_thousandth;
						calc_delay_state <= init;
						delay_string(6) <= character'val(character'pos('0') + digit);
						digit := 0; -- reset digit
					elsif( remainder = 0 ) then -- done with thousandths
						calc_delay_state <= init;
						delay_string(6) <= character'val(character'pos('0') + digit + 1);
						digit := 0; -- reset digit
					elsif( remainder > 0 ) then
						digit := digit + 1;
					end if;
				end case;
		end if;
	end process;

-- convert_delay_to_string: process(sample_delay)
	-- variable temp: integer range 0 to num_words16;
	-- begin
		-- delay_string(1) <= character'val(character'pos('0') + sample_delay/(10**6));
		-- temp := sample_delay mod 10**6;
		-- delay_string(2) <= character'val(character'pos('0') + temp/(10**5));
		-- temp := temp mod 10**5;
		-- delay_string(3) <= character'val(character'pos('0') + temp/(10**4));
		-- temp := temp mod 10**4;
		-- delay_string(4) <= character'val(character'pos('0') + temp/(10**3));
		-- temp := temp mod 10**3;
		-- delay_string(5) <= character'val(character'pos('0') + temp/(10**2));
		-- temp := temp mod 10**2;
		-- delay_string(6) <= character'val(character'pos('0') + temp/(10));
		-- temp := temp mod 10;
		-- delay_string(7) <= character'val(character'pos('0') + temp);
		-- delay_string(8 to 16) <= "         ";
-- end process;
		
			

lrclk_falling_edge: process(clk)
	begin
		if(clk'event and clk = '0') then
			lrclk_history(1) <= lrclk_history(0);
			lrclk_history(0) <= lrclk;
			case lrclk_history is
				when "10" =>
					lrclk_trigger <= true; -- falling edge event occurred
				when others =>
					lrclk_trigger <= false;
			end case;
		end if;
	end process;

process(clk)
			variable burst_count: integer range 0 to 1;
			variable wait_cycle: boolean;
			constant CAS_latency_high: integer := 2;
			variable CAS_latency: integer range 0 to 2;
			variable zero_data: boolean := true;
			variable read_pointer: integer range -delay_1sec to num_words16 + delay_1sec;
			variable write_pointer: integer range  0 to num_words16;
			variable temp_pointer: integer range -delay_1sec to num_words16-1;
			--variable button_history_inc: std_logic_vector(1 downto 0);
			--variable button_history_dec: std_logic_vector(1 downto 0);
			--variable button_history_mode: std_logic_vector(1 downto 0);
			variable increase: boolean;
			variable decrease: boolean;
			--variable delay_mode: delay_mode_t := (delay_1sec, delay_100ms, delay_10ms, delay_1ms);
			--variable current_mode: natural range 0 to 3;
		begin
		if(clk'event and clk = '0') then
			case audio_state is
				when start =>
						increment_ack <= '0';
						if(write_address = write_address_high) then
							zero_data := false;
							write_address <= delay_1sec;
							read_address <= 0;
							audio_state <= input_scan;
						else
							audio_state <= write_cmd;  -- zero the SDRAM contents for no huge pops
						end if;
				when input_scan =>
					read_pointer := read_address;
					write_pointer := write_address;
					
					if(write_pointer = write_address_high) then
						write_pointer := 0;
					end if;
					
					if(read_pointer = read_address_high) then
						read_pointer := 0;
					end if;
					
					-- button_history_dec(1) := button_history_dec(0);
					-- button_history_dec(0) := decrease_delay;
					-- button_history_inc(1) := button_history_inc(0);
					-- button_history_inc(0) := increase_delay;
					-- button_history_mode(1) := button_history_mode(0);
					-- button_history_mode(0) := mode;
					
					-- if(button_history_dec = "01") then
						-- decrease := true;
					-- else decrease := false;
					-- end if;
					-- if(button_history_inc = "01") then
						-- increase := true;
					-- else increase := false;
					-- end if;
					-- if(button_history_mode = "01") then
						-- if(current_mode = 3) then
							-- current_mode := 0;
							-- mode_state <= current_mode;
						-- else
							-- current_mode := current_mode + 1;
							-- mode_state <= current_mode;
						-- end if;
					-- end if;
					
					if( increase_delay = '1' ) then
						increase := true;
					else increase := false;
					end if;
					
					if( decrease_delay = '1' ) then
						decrease := true;
					else decrease := false;
					end if;
					
					if(increase or decrease) then
						increment_ack <= '1';
					end if;
					
					if(increase xor decrease) then -- ignore when both pressed
						if(increase) then -- increase delay by decreasing read_pointer
							if(read_pointer < write_pointer) then
								test <= true;
								read_pointer := read_pointer - increment;
									if(read_pointer < 0) then
										temp_pointer := read_pointer + num_words16;
										if(temp_pointer <= write_pointer) then -- max delay reached
											read_pointer := write_pointer + sample_stride;
											if(write_pointer = num_words16 - 1) then
												read_pointer := 0; -- special case at end of buffer
											end if;
										else -- temp_pointer > write_pointer 
											read_pointer := temp_pointer;
										end if;
									end if;
							else -- read_pointer >= write_pointer
								test <= false;
								read_pointer := read_pointer - increment;
								if(read_pointer <= write_pointer) then
									read_pointer := write_pointer + sample_stride; -- maximum delay reached
								end if;
							end if;
						elsif(decrease) then
							if(read_pointer < write_pointer) then
								read_pointer := read_pointer + increment;
								if(read_pointer >= write_pointer) then
									read_pointer := write_pointer - sample_stride; -- minimum sample delay
								end if;
							else -- read_pointer >= write_pointer
								read_pointer := read_pointer + increment;
								if(read_pointer > num_words16-1) then
									temp_pointer := read_pointer - (num_words16 - sample_stride);
									if(temp_pointer >= write_pointer) then -- went too far
										read_pointer := write_pointer - sample_stride;
									else
										read_pointer := temp_pointer;
									end if;
								end if;
							end if;
						end if;
					end if;
					
					write_address <= write_pointer; -- update addresses
					read_address <= read_pointer;
					
					audio_state <= idle; -- go to next state
					
				when idle =>
					increment_ack <= '0';
					if(lrclk_trigger) then -- start new cycle of madness
						audio_state <= write_cmd;
					
					end if;
				when write_cmd =>
					ram_address <= std_logic_vector(to_unsigned(write_address, 22));
					ram_enable <= true;
					read_nwrite <= false;  -- write command
					audio_state <= wait_for_ack;
				when wait_for_ack =>
					if(ack = true) then -- command received
						ram_enable <= false;
						if(read_nwrite) then
							audio_state <= cas_delay;
						else
							audio_state <= write_data;
						end if;
					else
					end if;
				when write_data =>
					if(burst_count = 1) then
						burst_count := 0;
						write_address <= write_address + 1;
						if(zero_data) then
							write_to_ram <= (others => '0');
							audio_state <= start;
						else
							write_to_ram <= i2s_data_received(23 downto 8); -- 16 MSBs of right channel
							audio_state <= delay;
						end if;
					else
						burst_count := burst_count + 1;
						write_address <= write_address + 1;
						if(zero_data) then
							write_to_ram <= (others => '0');
						else
						write_to_ram <= i2s_data_received(47 downto 32); -- 16 MSBs of left channel
						end if;
					end if;
				when delay =>
					audio_state <= read_cmd;
				when read_cmd =>
					ram_address <= std_logic_vector(to_unsigned(read_address, 22));
					ram_enable <= true;
					read_nwrite <= true; -- read command
					audio_state <= wait_for_ack;
				when cas_delay =>
					if(CAS_latency = CAS_latency_high) then
						audio_state <= read_data;
						CAS_latency := 0;
					else
						CAS_latency := CAS_latency + 1;
						
					end if;
				when read_data =>
					if(burst_count = 1) then
						if(mute = '1') then
							i2s_data_send <= (others => '0');
						else
							i2s_data_send(23 downto 8) <= read_from_ram;
							i2s_data_send(7 downto 0) <= (others => '0');
						end if;
						burst_count := 0;
						read_address <= read_address + 1;
						audio_state <= input_scan;
					else
						if(mute = '1') then
							i2s_data_send <= (others => '0');
						else
							i2s_data_send(47 downto 32) <= read_from_ram;
							i2s_data_send(31 downto 24) <= (others => '0');
						end if;
						burst_count := burst_count + 1;
						read_address <= read_address + 1;
					end if;
				end case;
			end if;
		end process;
			
end Muy_Bueno;









