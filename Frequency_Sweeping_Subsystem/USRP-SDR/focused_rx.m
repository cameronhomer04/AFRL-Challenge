%{
Project:        AFRL Challenge
Subsystem:      Frequency Sweeping
File:           focused_rx.m
Author:         Cameron Homer
Date:           09/25/2026
Description:    Helper function that handles the FOCUSED State
%}

function [iqdata] = focused_rx(USRP)

arguments (Input)
    USRP
end

arguments (Output)
    iqdata
end

[iqdata, ~, ~] = USRP();
end