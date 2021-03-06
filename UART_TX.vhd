----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date:    16:38:01 09/17/2017 
-- Design Name: 
-- Module Name:    UART_RX - Behavioral 
-- Project Name: 
-- Target Devices: 
-- Tool versions: 
-- Description: 
--
-- Dependencies: 
--
-- Revision: 
-- Revision 0.01 - File Created
-- Additional Comments: 
--
----------------------------------------------------------------------------------
----------------------------------------------------------------------
-- File Downloaded from http://www.nandland.com
----------------------------------------------------------------------
-- This file contains the UART Receiver.  This receiver is able to
-- receive 8 bits of serial data, one start bit, one stop bit,
-- and no parity bit.  When receive is complete o_rx_dv will be
-- driven high for one clock cycle.
-- 
-- Set Generic g_CLKS_PER_BIT as follows:
-- g_CLKS_PER_BIT = (Frequency of i_Clk)/(Frequency of UART)
-- Example: 10 MHz Clock, 115200 baud UART
-- (10000000)/(115200) = 87
--5208
library ieee;
use ieee.std_logic_1164.ALL;
use ieee.numeric_std.all;
USE IEEE.STD_LOGIC_UNSIGNED.ALL;
 
entity UART_RX is
  generic (
    g_CLKS_PER_BIT : integer := 5208;     -- Needs to be set correctly
	 DATA_WIDTH	:	INTEGER := 80--2088--64
    );
  port (
    i_Clk       : in  std_logic;
    i_RX_Serial : in  std_logic;
	 i_Reset		 : in	 std_logic;
   -- o_RX_DV     : out std_logic;
    o_RX_Byte   : out std_logic_vector(7 downto 0)
    );
end UART_RX;
 
 
architecture rtl of UART_RX is
 
  -- ******************** CONSTANTES ******************** 
  CONSTANT long_t		:	integer := DATA_WIDTH;
  
  type t_SM_State is (s_Idle, s_RX_Start_Bit, s_RX_Data_Bits,
                     s_RX_Stop_Bit, s_Cleanup);
  signal r_SM_Act_State : t_SM_State := s_Idle;
 
  signal r_RX_Data_R : std_logic := '0';
  signal r_RX_Data   : std_logic := '0';
   
  signal r_Clk_Count : integer range 0 to g_CLKS_PER_BIT-1 := 0;
  signal r_Bit_Index : integer range 0 to 7 := 0;  -- 8 Bits Total
  signal r_RX_Byte   : std_logic_vector(7 downto 0) := (others => '0');
  signal r_RX_DV     : std_logic := '0';
 
 -- SIGNAL preambulo	: unsigned(15 DOWNTO 0):="1010101010101010";
  SIGNAL idt			: std_logic_vector(7 DOWNTO 0):="00000001";
  SIGNAL lcu			: std_logic_vector(7 DOWNTO 0):="00000100";
  signal dat			: integer range 0 to long_t := 48;
 -- ******************** ENTRAMADO MS ********************
	--signal Data_in		:	unsigned(long_t-1 DOWNTO 0):= to_unsigned(11184642, DATA_WIDTH);--(others => '0'); -- TRAMA A GUARDAR EN LA MEMORIA
	signal Data_in		:	unsigned(long_t-1 DOWNTO 0):=(others => '0');
	signal Data_out	:	unsigned(long_t-1 DOWNTO 0):=(others => '0');
	signal Data_crc	:	unsigned(long_t-1 DOWNTO 0):=(others => '0');
	TYPE estados is (espera, agrega, recorre, conteo, limpia, recorre_crc);
	signal est_actual	: 	estados:= espera;
	signal contador  	:	NATURAL RANGE 0 TO 255 := 0;
	signal data		:	std_logic_vector(7 downto 0) := (others => '0');
	SIGNAL crcm			: STD_LOGIC:='0';
	
	-- ******************** SE�ALES CRC ******************** 
signal crc_temp : 			std_logic_vector(15 downto 0) := (others => '0'); -- Vector auxiliar para crc 
signal counter1 : 			integer := 0; -- Contador de iteraciones
signal crcout : 				std_logic_vector(15 downto 0);
signal crc_ini:				std_logic:='0';
--signal dato:					std_logic:='0';

-- ** Se�ales OOK
TYPE estadosOOK is (espera, conteo, envia);
signal est_OOK_actual	: 	estadosOOK:= espera;
signal temporal			: 	std_logic;
signal contador_OOK		: 	integer range 0 to 16666666 := 0;
SIGNAL r_OOK				:  std_logic:='0';
   
begin
 
  -- Purpose: Double-register the incoming data.
  -- This allows it to be used in the UART RX Clock Domain.
  -- (It removes problems caused by metastabiliy)
  p_SAMPLE : process (i_Clk)
  begin
    if rising_edge(i_Clk) then
      r_RX_Data_R <= i_RX_Serial;
      r_RX_Data   <= r_RX_Data_R;
    end if;
  end process p_SAMPLE;
   
 
  -- Purpose: Control RX state machine
  p_UART_RX : process (i_Clk)
  begin
    if rising_edge(i_Clk) then
         
      case r_SM_Act_State is
 
        when s_Idle =>
         -- r_RX_DV     <= '0';
          r_Clk_Count <= 0;
          r_Bit_Index <= 0;
          if r_RX_Data = '0' then       -- Start bit detected
            r_SM_Act_State <= s_RX_Start_Bit;
          else
            r_SM_Act_State <= s_Idle;
          end if;
 
           
        -- Check middle of start bit to make sure it's still low
        when s_RX_Start_Bit =>
          if r_Clk_Count = (g_CLKS_PER_BIT-1)/2 then
            if r_RX_Data = '0' then
              r_Clk_Count <= 0;  -- i_Reset counter since we found the middle
              r_SM_Act_State   <= s_RX_Data_Bits;
            else
              r_SM_Act_State   <= s_Idle;
            end if;
          else
            r_Clk_Count <= r_Clk_Count + 1;
            r_SM_Act_State   <= s_RX_Start_Bit;
          end if;
 
           
        -- Wait g_CLKS_PER_BIT-1 clock cycles to sample serial data
        when s_RX_Data_Bits =>
          if r_Clk_Count < g_CLKS_PER_BIT-1 then
            r_Clk_Count <= r_Clk_Count + 1;
            r_SM_Act_State   <= s_RX_Data_Bits;
          else
            r_Clk_Count            <= 0;
            r_RX_Byte(r_Bit_Index) <= r_RX_Data;
             
            -- Check if we have sent out all bits
            if r_Bit_Index < 7 then
              r_Bit_Index <= r_Bit_Index + 1;
              r_SM_Act_State   <= s_RX_Data_Bits;
            else
              r_Bit_Index <= 0;
              r_SM_Act_State   <= s_RX_Stop_Bit;
            end if;
          end if;
 
 
        -- Receive Stop bit.  Stop bit = 1
        when s_RX_Stop_Bit =>
          -- Wait g_CLKS_PER_BIT-1 clock cycles for Stop bit to finish
          if r_Clk_Count < g_CLKS_PER_BIT-1 then
            r_Clk_Count <= r_Clk_Count + 1;
            r_SM_Act_State   <= s_RX_Stop_Bit;
          else
            r_RX_DV     <= '1';
            r_Clk_Count <= 0;
            r_SM_Act_State   <= s_Cleanup;
				data <= r_RX_Byte;
          end if;
   
        -- Stay here 1 clock
        when s_Cleanup =>
          r_SM_Act_State <= s_Idle;
          r_RX_DV   <= '0';
             
        when others =>
          r_SM_Act_State <= s_Idle;
 
      end case;
    end if;
  end process p_UART_RX;
  
  --o_RX_DV   <= r_RX_DV;
  --o_RX_Byte <= r_RX_Byte;
   
p_DATA_FRAMING : process (i_Reset, i_Clk, r_RX_DV) 
	begin
		if i_Reset = '1' then
			est_actual <= espera;
			Data_in <= (others => '0');
		elsif rising_edge(i_Clk) then
			case est_actual is
				when espera =>
					if r_RX_DV = '1' then
						--contador <= contador + 1;
						est_actual <= conteo;
					else
						est_actual <= espera;
					end if;
					crcm <= '0';
				when conteo =>
--					if contador = 1 then
--						Data_in <= Data_in rol 8;
--					elsif contador = 5 then
--						crcm <= '1';
--						Data_in <= to_unsigned(11184642, Data_in'length);
--						contador <= 0;
--					else
--						crcm <= '0';
--					end if;
					if contador = 0 then
						Data_in(long_t-1 downto 40) <= (others => '0');
						Data_in(39 downto 0) <= "1010101010101010" & unsigned(idt) & unsigned(lcu) & "00000000"; 
						--Data_in <= Data_in rol 8;
					end if;
					contador <= contador + 1; 
					est_actual <= agrega;
				when agrega =>
					Data_in (7 downto 0) <= unsigned(data);
					if contador < 4 then
						est_actual <= recorre;
					else
						est_actual <= recorre_crc;
					end if;
				when recorre => 
					Data_in <= Data_in rol 8;
					--Data_out <= Data_in rol 8;
					est_actual <= espera;
				when recorre_crc =>
					Data_in <= Data_in rol 16;
					--Data_out <= Data_in rol 16;
					est_actual <= limpia;
				when limpia =>
					Data_crc <= Data_in;
					crcm <= '1';
					Data_in <= to_unsigned(11184642, Data_in'length);
					contador <= 0;
					est_actual <= espera;
			end case;
		end if;
	end process;
	
	--o_RX_Byte <=  std_logic_vector(Data_out (23 downto 16));
	--o_RX_Byte <= idt;
	
p_FRAME_COUNT : process (i_Reset, i_Clk, crcm) 
	begin
		if i_Reset = '1' then
			idt <= (others => '0');
		elsif rising_edge(i_Clk) then
			if crcm = '1' then
				if idt = "11111111" then
					idt <= "00000001";
				else
					idt <= idt + '1';
				end if;
			end if;
		end if;
	end process;
	
	p_CRC : process (i_Reset, i_Clk, crcm) 
	begin
		if i_Reset = '1' then
			crc_temp <= (others => '0');
		elsif rising_edge(i_Clk) then
			if crcm = '1' then
				crc_temp <= (others => '0');
				Data_out <= Data_crc;
				crc_ini <= '1';
			end if;
			if crc_ini = '1' then
				--dato <= Data_out((dat-1)-counter1);
				crc_temp(0) <= Data_out((dat-1)-counter1) xor crc_temp(15);
				crc_temp(1) <= crc_temp(0);
				crc_temp(2) <= Data_out((dat-1)-counter1) xor crc_temp(15) xor crc_temp(1);
				crc_temp(3) <= crc_temp(2);
				crc_temp(4) <= crc_temp(3);
				crc_temp(5) <= crc_temp(4);
				crc_temp(6) <= crc_temp(5);
				crc_temp(7) <= crc_temp(6);
				crc_temp(8) <= crc_temp(7);
				crc_temp(9) <= crc_temp(8);
				crc_temp(10) <= crc_temp(9);
				crc_temp(11) <= crc_temp(10);
				crc_temp(12) <= crc_temp(11);
				crc_temp(13) <= crc_temp(12);
				crc_temp(14) <= crc_temp(13);
				crc_temp(15) <= Data_out((dat-1)-counter1) xor crc_temp(15) xor crc_temp(14);
				counter1 <= counter1 + 1; -- Contador bit a bit de datos a enviar.
				if counter1 = 32 then
					counter1 <= 0;
					crcout <= crc_temp;
					Data_out(15 downto 0) <= unsigned(crc_temp);
					crc_ini <= '0';
					r_OOK <= '1';
				else
					crcout <= (others => '0');    -- La salida del CRC es cero durante el tiempo de espera de datos o inactividad.
					r_OOK <= '0';
				end if;
			end if;
		end if;
	end process;
	--o_RX_Byte <= std_logic_vector(Data_out (7 downto 0));
	
	p_OOK : process (i_Reset, i_Clk, r_OOK) 
	variable	contador2: integer;
	begin
		if i_Reset = '1' then
			est_OOK_actual <= espera;
		elsif rising_edge(i_Clk) then
			case est_OOK_actual is
				when espera =>
					if r_OOK = '1' then
						contador2 := long_t-1;
						est_OOK_actual <= envia;
					else
						est_OOK_actual <= espera;
					end if;
				when conteo =>
					o_RX_Byte <= (others => temporal); 
					if contador2 > 0 then
						contador2 := contador2 - 1;
						est_OOK_actual <= envia;
					else
						est_OOK_actual <= espera;
					end if;
				when envia =>
					if contador_OOK = 16666666 then
						temporal <= Data_out(contador2); 
						contador_OOK <= 0;
						est_OOK_actual <= conteo; 
					else
						contador_OOK <= contador_OOK+1;
						est_OOK_actual <= envia;
					end if;
			end case;
		end if;
	end process;
	
end rtl;