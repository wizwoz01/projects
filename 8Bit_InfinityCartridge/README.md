## FPGA UART Communication with M5StickCPlus2
This project demonstrates bidirectional UART communication between an M5StickCPlus2 (ESP32-based) and an FPGA, with file transfer capabilities over WiFi.

## Features
# UART Communication:

115200 baud rate

HardwareSerial using GPIO26 (TX) and GPIO36 (RX)

Bidirectional data transfer

# File System:

LittleFS for file storage

Automatic filesystem formatting on startup

File listing capability

# WiFi Connectivity:

Connects to specified WiFi network

Downloads ROM files from the internet

Verifies downloaded files

# FPGA File Transfer:

Buffered transfer with progress display

Visual feedback on M5StickCPlus2 screen

Error handling

# User Interface:

Status display on M5StickCPlus2 LCD

Progress bar for file transfers

Error messages

## Hardware Setup
Connections
M5StickCPlus2	FPGA
GPIO26 (TX)	FPGA RX
GPIO36 (RX)	FPGA TX
GND	GND
## Note: GPIO36 is input-only on the ESP32.

## Software Commands
Send these commands via Serial Monitor (115200 baud):

FETCH_ROM - Downloads Ultima I disk image from archive.org

LIST_FILES - Lists all files in LittleFS

SEND - Transfers the ROM file to FPGA

## FPGA Implementation
The FPGA side includes:

UART receiver/transmitter state machine

Large FIFO buffer (140KB) for file transfer

Status LEDs

Error handling

## Key FPGA Modules:
UART_FIFO - Large circular buffer for data

UART_rx_tx - UART communication state machine

## Usage
Upload the sketch to M5StickCPlus2

Open Serial Monitor at 115200 baud

Use commands to manage files and transfers

Monitor progress on the M5StickCPlus2 display

## Requirements
## Libraries:
LittleFS

WiFi

M5StickCPlus2

HardwareSerial

## Hardware:
M5StickCPlus2

FPGA board with UART capability

WiFi network access

## Notes
The code automatically formats LittleFS on startup (erases all files)

GPIO36 is input-only on ESP32

## NOT COMPLETE.....
## Features that need to still be implemented:
Complete Circuitry/Expansion Card to connect the sOc to Apple IIe computer.

Hijack the 6502 bus to run transmitted files on the Apple IIe computer.

If successful, the Apple IIe will be able to connect to WIFI, download
applications or games and Run on the machine.
