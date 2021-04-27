
`define  ADDR_WIDTH 8
`define  CMD_DATA_WIDTH 32

`define  WRITE 2'b10          //Register operation command
`define  READ  2'b01
`define  IDLE  2'b00

`define SLV0_RW_ADDR 8'h00    //Register address 
`define SLV1_RW_ADDR 8'h04
`define SLV2_RW_ADDR 8'h08
`define SLV0_R_ADDR  8'h10
`define SLV1_R_ADDR  8'h14
`define SLV2_R_ADDR  8'h18


`define SLV0_RW_REG 0
`define SLV1_RW_REG 1
`define SLV2_RW_REG 2
`define SLV0_R_REG  3
`define SLV1_R_REG  4
`define SLV2_R_REG  5

`define FIFO_MARGIN_WIDTH 8

`define PRIO_WIDTH 2
`define PRIO_HIGH 2
`define PRIO_LOW  1

`define PAC_LEN_WIDTH 3
`define PAC_LEN_HIGH 5
`define PAC_LEN_LOW  3    
