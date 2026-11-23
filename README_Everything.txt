===============================================================================
  FREQUENCY-HOPPING DQPSK MESH NETWORK  -  OPERATOR GUIDE
  USRP B210 / X310, MATLAB, A* routing
===============================================================================

CONTENTS
  1. What the system does
  2. What you need
  3. Quick start: the three-node demo (TX -> repeater -> RX)
  4. Step 1 - Make the route  (Astar_2D_route_Version2.m)
  5. Step 2 - Set up each node  (runNode_FH.m)
  6. Step 3 - Start the nodes and read the results
  7. Settings reference
  8. Radio settings  (qpskConfig.m)
  9. Troubleshooting
 10. File list


-------------------------------------------------------------------------------
1. WHAT THE SYSTEM DOES
-------------------------------------------------------------------------------
An alert (a hex message) is sent from one radio to another through a chain
of radios (a mesh). Three things make it work:

  * A* ROUTING. Astar_2D_route_Version2.m finds the best path across a grid
    of squares and turns it into a "routing number": the list of SDR IDs the
    message must pass through, in order (e.g. SDR 1 -> 2 -> 3). The routing
    number is saved to route_hex.mat.

  * PI/4-DQPSK MODEM. Each packet is
        [ preamble | length | hop header | route | message | CRC-16 ]
    The route travels inside every packet, so only the sending node needs
    route_hex.mat.

  * FREQUENCY HOPPING. Every node changes channel every "dwell" seconds,
    following a pseudo-random sequence made from a shared key (hopKey).
    All nodes must use identical hopping settings.

HOW A MESSAGE MOVES (route 1 -> 2 -> 3)
  1. SDR 1 removes its own ID and sends route [2, 3].
  2. SDR 3 hears it, but the first ID is 2, not 3, so it ignores it
     (when strictNextHop = true).
  3. SDR 2 sees its own ID first, removes it and sends route [3].
  4. SDR 3 sees its own ID first and last: DELIVERED.


-------------------------------------------------------------------------------
2. WHAT YOU NEED
-------------------------------------------------------------------------------
  * MATLAB with the Communications Toolbox and the "Communications Toolbox
    Support Package for USRP Radio". Astar_2D_route_Version2.m uses clim(),
    which needs MATLAB R2022a or newer.
  * One computer (or one MATLAB session) per radio. Each node runs its own
    copy of runNode_FH.m.
  * The full project folder copied onto every computer. Keep every .m file
    in the same folder (see section 10).
  * Bench testing: connect radios with cables through 30 dB or more of
    attenuation, or keep TX gain low. The default band (910-920 MHz) is
    inside the 902-928 MHz ISM band; check the rules before transmitting
    over the air.


-------------------------------------------------------------------------------
3. QUICK START: THE THREE-NODE DEMO
-------------------------------------------------------------------------------
Goal: SDR 1 raises an alert, SDR 2 relays it, SDR 3 receives it. The radios
sit close together, so SDR 3 could hear SDR 1 directly. strictNextHop = true
makes SDR 3 wait for the relay so the demo shows every hop.

  a) On any computer, run Astar_2D_route_Version2.m (section 4).
     Check the Command Window shows "Hop order: 1 -> 2 -> 3".
  b) Copy route_hex.mat into the project folder on SDR 1's computer.
  c) On each computer, open runNode_FH.m and set:

        Setting          SDR 1 (sender)   SDR 2 (relay)    SDR 3 (receiver)
        -------------    --------------   --------------   ----------------
        role             "tx"             "repeater"       "rx"
        myId             1                2                3
        originate        (not used)       false            (not used)
        strictNextHop    true             true             true
        useAstarRoute    true             true             true
        runDuration      30               Inf              Inf
        radioChoice      radio on that computer: 'B210', 'X310' or 'any'

     (SDR 1 can also be role "repeater" with originate = true: it then sends
      one burst and stops, which avoids sharing the air with SDR 2.)

  d) Start SDR 2 and SDR 3 first. Wait until both are listening.
  e) Start SDR 1.
  f) SDR 3 should print "Ignored ... next hop is SDR 2" first, then
     "Received:" with "This node (SDR 3) is the destination: delivered."

To show normal (non-demo) behaviour, set strictNextHop = false on SDR 3:
it then accepts the message as soon as it hears SDR 1, skipping SDR 2.


-------------------------------------------------------------------------------
4. STEP 1 - MAKE THE ROUTE  (Astar_2D_route_Version2.m)
-------------------------------------------------------------------------------
Edit only the sections below, then press Run. The script plots the map and
path, writes route_list.csv, and saves route_hex.mat (via fhSaveRoute).

The grid: every square is a location. sdrBank says which SDR(s) sit in each
square. Coordinates are always [row, col]. On the plot, X = column, Y = row.

  SECTION "Build the map"
    rows, cols        Size of the grid.  Current: rows = 3; cols = 1;
                      (a 3-square column, one SDR per square)

  SECTION "Fixed walls"  (inside %{ ... %} - remove those lines to use it)
    map(r, c) = 1     Marks a square as an obstacle (no path through it).
                      Example: map(2, 1:5) = 1;  blocks row 2, columns 1-5.
                      Every index must fit inside rows x cols.

  SECTION "Random rectangular obstacles"  (inside %{ ... %})
    rng(1), k = 1:5   Seed and number of random blocks. Simulation only;
                      leave commented out for hardware runs.

  START AND GOAL
    start = [1, 1];   Square of the node that raises the alert.
    goal  = [3, 1];   Square of the destination node.
                      Both squares MUST contain an SDR in sdrBank.

    allowDiagonal     true = 8 directions, false = up/down/left/right only.

  SECTION "SDR bank" - choose ONE option
    Option A (simulation): sdrsPerCell + autoSdrBank numbers SDRs for you.
    Option B (hardware, currently used): list your real radios by hand:
        sdrBank = cell(rows, cols);
        sdrBank{1, 1} = 1;      % SDR 1 in row 1, col 1
        sdrBank{2, 1} = 2;      % SDR 2 in row 2, col 1
        sdrBank{3, 1} = 3;      % SDR 3 in row 3, col 1
    The number here is the radio's SDR ID. It MUST equal myId in runNode_FH
    on that radio's computer. A square with no SDR becomes a dead square
    the path cannot use. More SDRs in a square = higher cost to cross it.

    numSdrs           Set automatically from the bank. If some fleet IDs
                      are not in the bank, set it to the fleet size after
                      applySdrBank, e.g. numSdrs = 16;

  SECTION "Node weights"
    baseWeight        Extra cost per square (1 = none). Load your own with
                      baseWeight = readmatrix('weights.csv'); (same size as
                      the map). Higher weight = A* avoids that square.

  WHAT TO CHECK IN THE OUTPUT
    "Path found: ..."                     a path exists
    "SDRs on route (3 of 3): [1 2 3]"     the radios the alert will visit
    "Hop order: 1 -> 2 -> 3. The originator (myId) must be SDR 1."
    "Routing number saved to route_hex.mat ... ordered format"
    "Room left in each packet for the message: N hex characters"

  Then copy route_hex.mat next to runNode_FH.m on the SENDING computer only
  (the node in the start square). Relays and receivers read the route from
  the packets. Re-run and re-copy whenever the map or bank changes.


-------------------------------------------------------------------------------
5. STEP 2 - SET UP EACH NODE  (runNode_FH.m)
-------------------------------------------------------------------------------
runNode_FH.m is the one script every node runs. Change ONLY the
"NODE SETTINGS" section per computer. The "HOPPING SETTINGS" section must
be IDENTICAL on every computer.

ROLES (role = ...)
  "tx"        Sends the alert continuously, hopping every dwell. Removes its
              own ID from the route first. Needs route_hex.mat and myId equal
              to the first SDR on the route.
  "repeater"  Listens; when its ID is next on the route it relays the alert
              as one burst. With originate = true it also raises the alert
              itself (one burst), so it needs route_hex.mat.
              Shows a summary figure at the end.
  "rx"        Receiver with a live window. Finds the transmitter, follows
              its hops and prints each message.
  "both"      One-radio loopback test (TX cabled to RX through 30 dB+).
              Measures every channel; use it to find bad channels.

NODE SETTINGS - change per computer
  role             "tx", "rx", "repeater" or "both"
  radioChoice      'any', 'B210' or 'X310' - which attached radio to use
  x310Addresses    X310 IP(s) if the search misses it, e.g. {'192.168.10.2'}
  hexMessages      The alert, in hex (sender only), e.g. "1100A0C".
                   Several messages take turns: ["DEAD", "BEEF"].
                   Repeater originator sends only the first.
  messageInterval  Seconds on each message when several are listed.
  useAstarRoute    true = put the A* route in front of every message.
                   Must be true for "repeater".
  routeFile        "route_hex.mat" - file saved by the A* script.
  routeHex         Type a routing number here to override routeFile
                   (leave "" to use the file).
  myId             THIS radio's SDR ID - must match sdrBank in the A* script.
  strictNextHop    DEMO SWITCH (rx and repeater):
                     true  = accept a message only when this node is next on
                             the route, i.e. after the node before it relayed.
                     false = accept any message whose route lists this node.
  originate        Repeater only: true on the node that raises the alert.
  txGuard          Repeater: extra wait (s) after a burst ends before
                   relaying. Raise to 0.3-0.5 if bursts overlap.
  runDuration      Seconds to run. Use Inf on relays and receivers.
  showPlots        Live windows / summary figure on or off.
  saveSlotLog      Save a CSV of slots ("both") or events ("repeater").

  RX tuning (usually leave as is)
  framesPerBlock   Frames decoded per pass (default 4).
  useBurstMode     true; set false if your MATLAB rejects burst mode.
  acquireMode      "scan" (fast) or "park".
  scanBlocks       Blocks on each channel while scanning.
  lostAfterSlots   Slots without a packet before searching again.
  rxLatency        0; raise to ~0.03 on a B210 over USB if the summary
                   reports many "packets from a channel already left".

  "both" (loopback) only
  printEachSlot, minPacketsPerSlot, adaptiveHopping, surveyVisits,
  minPassRate, minPacketRate, minChannels - see the comments in the file.

HOPPING SETTINGS - SAME ON EVERY NODE
  fc               Centre of the band (Hz). Default 915e6.
  nCh              Number of channels (even number). Default 10.
  chSpacing        Channel spacing (Hz). Default 1e6 -> band 910-920 MHz.
  dwell            Seconds on each channel. Default 0.5 (0.1 minimum).
  hopKey           Shared key, whole number below 2^32.
  slotGuard        Part of each slot kept silent while retuning (0.15).
  pktGap           Silence between packets (0.25 of a packet).
  excludeChannels  Channels never used, e.g. [3 7] (from a "both" run).
  burstSeconds     Repeater burst length. Leave "auto".
  If any of these differ between nodes, they will not hear each other.


-------------------------------------------------------------------------------
6. STEP 3 - START THE NODES AND READ THE RESULTS
-------------------------------------------------------------------------------
ORDER
  1. Start relays and receivers first (they listen).
  2. Start the sender last.
  The script lists the radios it found and which one it picked; check this
  is the right radio.

WHAT TO LOOK FOR
  Sender ("tx")
    "TX sends route 2... (SDR 1 removed): next hop SDR 2."
    A small window with a Stop button. Underruns should stay near 0.

  Relay ("repeater")
    "Burst for me ... Forwarding to SDR 3 in x.xx s"
    "Burst sent (0 underruns). Listening again."
    Later: "Heard a burst for SDR 3 ... not mine, ignored." (normal: it
    hears its own relay being passed on)

  Receiver ("rx")
    "Locked to the transmitter at slot N."
    strict mode: "Ignored: ... next hop is SDR 2, not SDR 3: waiting for
    the relay" (packets straight from SDR 1)
    "Received: <payload>" then "This node (SDR 3) is the destination:
    delivered."

  Destination as "repeater"
    "*** DELIVERED: message ... This node, SDR 3, is the destination. ***"

STOPPING
  Press Stop in the live window, or Ctrl+C in the Command Window. The radios
  are released automatically. If MATLAB was killed, unplug/replug the B210
  or restart MATLAB before running again.

SAVED OUTPUT (in the current folder)
  route_list.csv                    every square on the A* path
  route_hex.mat                     routing number for the sender
  fh_repeater_log_SDR<n>_<time>.csv one row per repeater event
  fh_slot_log_<time>.csv            one row per slot ("both" role)
  Workspace variables: txStats, rxStats, rpStats, lbStats, eventTable,
  slotTable. Redraw a repeater summary with fhRepeaterSummary(rpStats, fh).


-------------------------------------------------------------------------------
7. SETTINGS REFERENCE - WHERE TO CHANGE WHAT
-------------------------------------------------------------------------------
  I want to...                        File / variable
  ----------------------------------  ---------------------------------------
  Change the map size                 Astar_2D_route_Version2.m: rows, cols
  Add obstacles                       Astar_2D_route_Version2.m: map(r,c) = 1
  Change sender / destination square  Astar_2D_route_Version2.m: start, goal
  Place or add radios on the map      Astar_2D_route_Version2.m: sdrBank{r,c}
  Make A* avoid an area               Astar_2D_route_Version2.m: baseWeight
  Set which radio this computer is    runNode_FH.m: myId
  Choose what this node does          runNode_FH.m: role
  Change the alert text               runNode_FH.m: hexMessages
  Use a typed route, not the file     runNode_FH.m: routeHex
  Demo: force every hop               runNode_FH.m: strictNextHop = true
  Pick the B210 or the X310           runNode_FH.m: radioChoice
  Find an X310 on the network         runNode_FH.m: x310Addresses
  Run forever                         runNode_FH.m: runDuration = Inf
  Change band / channels / speed      runNode_FH.m: fc, nCh, chSpacing,
                                      dwell  (ALL nodes)
  Skip bad channels                   runNode_FH.m: excludeChannels (ALL)
  Change TX / RX gain                 qpskConfig.m: txGain, rxGain
  Change which radio port is used     qpskConfig.m: txChannel, rxChannel


-------------------------------------------------------------------------------
8. RADIO SETTINGS  (qpskConfig.m)
-------------------------------------------------------------------------------
Must be the same file on every node. Normally only gains and channels change.

  cfg.platforms.B210.txGain / rxGain   dB, range about 0-89.75 (default 50)
  cfg.platforms.X310.txGain / rxGain   daughterboard scale, about 0-31.5
                                       (defaults 15 / 20)
  txChannel / rxChannel                1 = port/side A, 2 = side B
                                       (default TX on 1, RX on 2)

  Too many "checksum FAILED" with a strong signal -> lower TX gain or add
  attenuation (overload). Weak or "no packet" -> raise RX gain, then TX gain.

  Do NOT change symbolRate, samplesPerSymbol, rolloff, preambleLength,
  masterClockRate, interpFactor or decimFactor unless every node is changed
  together; the file checks the sample rates and stops if they do not match.


-------------------------------------------------------------------------------
9. TROUBLESHOOTING
-------------------------------------------------------------------------------
  Message                                        What to do
  ---------------------------------------------  ------------------------------
  "No routing number: route_hex.mat not found"   Run the A* script and copy
                                                 route_hex.mat next to
                                                 runNode_FH.m, or type routeHex.
  "The route starts at SDR x but myId is y"      Wrong radio or wrong myId.
                                                 Run the sender on SDR x.
  "Route ... is a bitmask / sorted list"         Re-run the A* script; copy the
                                                 new route_hex.mat everywhere.
  "The start and goal squares must each          Put an SDR in sdrBank at start
   contain at least one SDR"                     and at goal.
  "No path found"                                Walls or dead squares block
                                                 every way; check the map/bank.
  No radio found / wrong radio picked            Check USB/Ethernet, set
                                                 radioChoice, add the X310 IP
                                                 to x310Addresses.
  Receiver never locks                           Hopping settings differ
                                                 between nodes (fc, nCh,
                                                 chSpacing, dwell, hopKey,
                                                 excludeChannels), or gain is
                                                 too low.
  "Heard slot N, past the end of a burst"        Normal when the sender is
                                                 "tx": the relay forwards the
                                                 first burst only.
  Many "packets from a channel already left"     Set rxLatency = 0.03, or
                                                 showPlots = false.
  Underruns on the sender                        Close other programs, turn off
                                                 showPlots, or use a longer
                                                 dwell.
  Relay starts while the previous node is on     Raise txGuard (0.3 - 0.5).
  air
  Destination delivers twice                     strictNextHop = false: it heard
                                                 the sender and the relay. Logged
                                                 as "duplicate"; set true for
                                                 the demo.
  "framesPerBlock ... is too small"              Use the number the error gives.
  Radio busy after a crash                       Restart MATLAB or replug the
                                                 B210.


-------------------------------------------------------------------------------
10. FILE LIST  (all in the same folder on every computer)
-------------------------------------------------------------------------------
  Run these:
    Astar_2D_route_Version2.m   make the route (saves route_hex.mat)
    runNode_FH.m                run a node
    qpskConfig.m                radio and modem settings

  Routing:
    autoSdrBank, applySdrBank, bankToWeights, routeToSdrMask, hexToSdrList,
    isSdrOnRoute, fhSaveRoute, fhAddRoute, fhSplitRoute, fhNextHop

  Frequency hopping:
    fhConfig, fhHopSequence, fhTune, fhRxFollow, fhHeaderBits, fhReadHeader,
    fhCrc8, fhPacketLayout, fhBuildSlotFrame, fhHopDisplay,
    fhRunTransmitter, fhRunReceiverLoop, fhRunLoopback, fhRunRepeater,
    fhRepeaterSummary

  Modem and radios:
    findSdrRadios, selectSdrRadio, setupSdrNode, releaseSdrNode,
    createSdrTransmitter, createSdrReceiver, captureBlock, receivePacket,
    detectPacket, correctFrequencyOffset, dqpskModulate, dqpskDemodulate,
    pulseShapeTx, buildPacketBits, makePreambleBits, payloadChecksum,
    hexToBits, bitsToHex, createLiveRxDisplay, updateLiveRxDisplay,
    spectrumDbfs

  When a file is updated, copy the new version to EVERY computer. Mixed
  versions are the most common cause of nodes not hearing each other.
===============================================================================
