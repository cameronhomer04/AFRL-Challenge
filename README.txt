#########################README ##############################

##################THIS FILE IS INCOMPLETE#####################

All functions within the files work, however additional operations will be added to the system to make the transmission process better

Goal:

This folder creates the pathways from SDR to SDR. 

Information:

This system uses the DQPSK modulation type to transmit a created payload.
The payload can be however long it needs to be.



Operating the Functions:

runNode.m

	This is where the user defines what type of SDR the node is going to be.

	I recommend using 'Both' for testing purposed as it allows for transmission and reception while only using one SDR


qpskConfig.m
	
	This is where the user defines the signal that will be sent. Meaning gain of the receiver and transmitter will be defined here, along with operational frequency.

				#####	IMPORTANT	#####
	
	Makes sure the frequency used is attuned to the antenna that you are using.

	The antennas are sensitive so be careful with the amount of gain used. You may have to try different gain values to get a good reading. 

What needs to be done: 

This file is incomplete because the none of the current classes of SDR act as a repeater. This 'repeater' class act as a receiver first, decoder (checking if they're in the routing number), and finally as a transmitter. The current classes of SDRs do not do this, so expect updated files in the future. (10.30.26)
