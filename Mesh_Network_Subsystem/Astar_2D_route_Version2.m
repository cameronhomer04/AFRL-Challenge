%% A* path planning on a 2D occupancy grid
% Map convention: 0 = free cell, 1 = obstacle.
% Coordinates are [row, col]. Requires MATLAB R2016b+ (local functions in scripts).
% SDR bank files needed in the same folder: autoSdrBank.m, applySdrBank.m,
% bankToWeights.m, routeToSdrMask.m, hexToSdrList.m, isSdrOnRoute.m

clear; clc; close all;
%% Things to change when building a new map
%{

Change:
    rows/cols -- Build the map
    Walls 
    Random blocks
    Starting and ending information
    SDRs per cell 
    
%}
%% ---------------- Build the map ----------------
rows = 10; cols = 10;
map  = zeros(rows, cols);

% Fixed walls
%{
map(10, 5:45)  = 1;          % horizontal wall
map(1:40, 47) = 1;          % vertical wall
map(25, 15:45) = 1;          % horizontal wall
map(25:48, 15) = 1;          % vertical wall
map(35:50, 30) = 1;          % wall from bottom
map(1:20, 25)  = 1;          % wall from top
map(25, 30:33) = 0;          % gap in a wall
%}

%% Random rectangular obstacles

rng(1);
for k = 1:5
    h = randi([2 5]); w = randi([2 6]);
    r = randi([1 rows-h]); c = randi([1 cols-w]);
    map(r:r+h-1, c:c+w-1) = 1;
end


start = [1, 1];         % [row, col]
goal  = [10, 10];       % [row, col]
map(start(1), start(2)) = 0;   % make sure endpoints are free
map(goal(1),  goal(2))  = 0;

allowDiagonal = false;   % 8-connected if true, 4-connected if false

%% ---------------- SDR bank ----------------
% Each square has its SDR(s) at the centre. sdrBank{row, col} lists the IDs
% of every SDR in that square; [] means no SDR (the square becomes a dead node).
% The bank drives the routing: the number of SDRs in a square becomes its
% weight (see Node weights below), so editing the bank changes the path.
%
% Option A (simulation): number SDRs automatically from a count per square


sdrsPerCell = ones(rows, cols);         % 1 SDR in a normal square
%{
sdrsPerCell(30:40, 20:50) = 5;          % example: squares that need 5 SDRs
sdrsPerCell(5:15, 30:40)  = 3;          % example: squares that need 3 SDRs
%}
sdrBank = autoSdrBank(map, sdrsPerCell);

%
% Option B (hardware): place your real SDRs by hand instead of Option A
%   sdrBank = cell(rows, cols);
%   sdrBank{1, 1} = 1;                  % SDR 1 in square (row 1, col 1)
%   sdrBank{1, 2} = 2;
%   sdrBank{2, 2} = [3 4 5 6 7];        % a square that needs 5 SDRs
% Watch the order: sdrBank{row, col}. The plot's data tip shows X = col, Y = row.
%
% Either way, you can edit single squares afterwards, e.g.
%   sdrBank{3, 9} = [101 102 103 104 105];   % make (3,9) a 5-SDR square

[map, numSdrs] = applySdrBank(map, sdrBank);   % squares without SDRs -> dead nodes
% numSdrs sets the routing number width; every SDR must use the same value.
% Set it to your fleet size if not all IDs are in the bank, e.g. numSdrs = 16;
if isempty(sdrBank{start(1), start(2)}) || isempty(sdrBank{goal(1), goal(2)})
    error('The start and goal squares must each contain at least one SDR.');
end
fprintf('SDR bank: %d SDRs in %d squares.\n', numSdrs, nnz(~cellfun(@isempty, sdrBank)));

%% ---------------- Node weights ----------------
% Worked out from the bank: weight = baseWeight x (number of SDRs in the square).
% Entering a square costs (step length) x (its weight).
% Put any other cost factors you calculate elsewhere into baseWeight, e.g.
%   baseWeight = readmatrix('weights.csv');
baseWeight = ones(rows, cols);          % 1 = no extra cost
nodeWeight = bankToWeights(sdrBank, baseWeight);

%% ---------------- Run A* ----------------
tic;
[path, cost, explored] = astar(map, start, goal, allowDiagonal, nodeWeight);
t = toc;

if isempty(path)
    fprintf('No path found (%.3f s, %d cells explored).\n', t, nnz(explored));
else
    fprintf('Path found: %d steps, cost %.2f, %d cells explored, %.3f s.\n', ...
            size(path,1)-1, cost, nnz(explored), t);
end

%% ---------------- Route list ----------------
if ~isempty(path)
    route = buildRouteList(path, size(map), nodeWeight);
    route.SDRs = cellfun(@mat2str, sdrBank(route.NodeID), 'UniformOutput', false);

    fprintf('\nFull route (every node visited):\n');
    disp(route);

    % Waypoints = start, goal, and every node where the heading changes
    waypoints = route(route.IsWaypoint, :);
    fprintf('Waypoints (%d of %d nodes):\n', height(waypoints), height(route));
    for k = 1:height(waypoints)
        fprintf('  %2d) Node %4d  (row %2d, col %2d)  cumulative cost %6.2f\n', ...
                k, waypoints.NodeID(k), waypoints.GridRow(k), waypoints.GridCol(k), ...
                waypoints.CumCost(k));
    end

    % Save for use elsewhere (e.g. as a forwarding list)
    % If route_list.csv is locked (open in Excel, OneDrive syncing, read-only),
    % save to a timestamped file instead of stopping the script.
    outFile = 'route_list.csv';
    try
        writetable(route, outFile);
    catch err
        altFile = sprintf('route_list_%s.csv', datestr(now, 'yyyymmdd_HHMMSS'));
        warning('Could not write %s (%s)\nIs it open in Excel? Saving to %s instead.', ...
                outFile, err.message, altFile);
        outFile = altFile;
        writetable(route, outFile);
    end
    fprintf('\nRoute saved to %s\n', outFile);

    % SDR routing number: the shorter of a bitmask ('0'...) or an ID list ('1'...).
    % Needs routeToSdrMask.m and hexToSdrList.m in the same folder.
    [sdrHex, sdrList, ~, sdrFormat] = routeToSdrMask(path, sdrBank, numSdrs);
    fhSaveRoute(sdrHex, sdrList, numSdrs);
    fprintf('\nSDRs on route (%d of %d): %s\n', numel(sdrList), numSdrs, mat2str(sdrList'));
    if numel(sdrHex) <= 64
        fprintf('SDR routing number (%s, %d hex digits): %s\n', sdrFormat, numel(sdrHex), sdrHex);
    else
        fprintf('SDR routing number (%s, %d hex digits): %s...\n', sdrFormat, numel(sdrHex), sdrHex(1:64));
    end

    % Round-trip check: decoding must give back the same SDRs
    assert(isequal(hexToSdrList(sdrHex), sdrList), 'SDR routing number mismatch.');
    % On an SDR, the forwarding check is:  isSdrOnRoute(sdrHex, myId)
end

%% ---------------- Plot ----------------
if isempty(path), waypoints = []; end
minW = min(nodeWeight(map == 0));
maxW = max(nodeWeight(map == 0));
isWeighted = (nodeWeight > minW) & (map == 0);   % nodes costing more than the cheapest

figure('Color','w','Name','A* path planning','Position',[100 100 1300 520]);

% ---- Panel 1: search map with weighted regions tinted and outlined ----
ax1 = subplot(1, 2, 1);
mapImg = zeros(rows, cols);       % 0 free, 1 explored, 2 obstacle
mapImg(explored) = 1;
mapImg(map == 1) = 2;
imagesc(ax1, mapImg);
colormap(ax1, [1 1 1; 0.80 0.88 1.00; 0.15 0.15 0.15]);
clim(ax1, [0 2]);
axis(ax1, 'equal', 'tight'); hold(ax1, 'on');

% Orange tint: the heavier the node, the stronger the tint
if maxW > minW
    tintAlpha = 0.15 + 0.45 * (nodeWeight - minW) / (maxW - minW);
    tintAlpha(~isWeighted) = 0;
    tint = cat(3, ones(rows, cols), 0.55 * ones(rows, cols), zeros(rows, cols));
    image(ax1, tint, 'AlphaData', tintAlpha);
    % Dashed outline around every weighted region
    contour(ax1, double(isWeighted), [0.5 0.5], 'LineColor', [0.85 0.4 0], ...
            'LineStyle', '--', 'LineWidth', 1.2);
end

drawGrid(ax1, rows, cols);
drawPathOverlay(ax1, path, waypoints, start, goal);
title(ax1, sprintf('A* path (cost %.2f): explored = blue, weighted = orange', cost));
xlabel(ax1, 'column'); ylabel(ax1, 'row');

% ---- Panel 2: node-weight heat map ----
ax2 = subplot(1, 2, 2);
imagesc(ax2, nodeWeight);
colormap(ax2, parula);
if maxW > minW, clim(ax2, [minW maxW]); end
cb = colorbar(ax2);
cb.Label.String = 'node weight';
axis(ax2, 'equal', 'tight'); hold(ax2, 'on');

% Obstacles drawn in black over the heat map
image(ax2, zeros(rows, cols, 3), 'AlphaData', double(map == 1));

drawGrid(ax2, rows, cols);
drawPathOverlay(ax2, path, waypoints, start, goal);
title(ax2, sprintf('Node weights (min %.2f, max %.2f), obstacles in black', minW, maxW));
xlabel(ax2, 'column'); ylabel(ax2, 'row');

%% ======================================================================
%                              LOCAL FUNCTIONS
%  ======================================================================
function [path, cost, closed] = astar(map, start, goal, allowDiagonal, nodeWeight)
% A* search on an occupancy grid with per-node weights.
%   map           - logical/numeric grid, nonzero = obstacle
%   start, goal   - [row, col]
%   allowDiagonal - true for 8-connectivity (no corner cutting)
%   nodeWeight    - (optional) positive matrix, same size as map; cost of
%                   entering a node = step length x nodeWeight(node)
% Returns:
%   path   - N-by-2 list of [row, col] from start to goal ([] if none)
%   cost   - total path cost (Inf if none)
%   closed - logical mask of expanded cells

    [rows, cols] = size(map);
    sz = [rows, cols];

    if map(start(1), start(2)) || map(goal(1), goal(2))
        error('Start or goal is inside an obstacle.');
    end

    if nargin < 5 || isempty(nodeWeight)
        nodeWeight = ones(rows, cols);
    end
    if ~isequal(size(nodeWeight), [rows, cols])
        error('nodeWeight must be the same size as map (%d x %d).', rows, cols);
    end
    if any(nodeWeight(:) <= 0) || any(isnan(nodeWeight(:)))
        error('All node weights must be positive numbers.');
    end

    % Scale the heuristic by the cheapest free node so it never overestimates
    % (keeps A* optimal for any positive weights).
    hScale = min(nodeWeight(map == 0));

    if allowDiagonal
        moves = [-1 0; 1 0; 0 -1; 0 1; -1 -1; -1 1; 1 -1; 1 1];
        stepCost = [1 1 1 1 sqrt(2) sqrt(2) sqrt(2) sqrt(2)];
    else
        moves = [-1 0; 1 0; 0 -1; 0 1];
        stepCost = [1 1 1 1];
    end

    startIdx = sub2ind(sz, start(1), start(2));
    goalIdx  = sub2ind(sz, goal(1),  goal(2));

    g        = inf(sz);          % cost from start
    f        = inf(sz);          % g + heuristic
    parent   = zeros(sz);        % linear index of predecessor
    closed   = false(sz);
    openMask = false(sz);

    g(startIdx)        = 0;
    f(startIdx)        = hScale * heuristic(start, goal, allowDiagonal);
    openMask(startIdx) = true;

    found = false;
    while any(openMask(:))
        % Pick the open node with the lowest f (ties broken by lowest h)
        openIdx = find(openMask);
        fOpen   = f(openIdx);
        best    = openIdx(fOpen == min(fOpen));
        if numel(best) > 1
            hb = f(best) - g(best);
            [~, k] = min(hb);
            best = best(k);
        end
        current = best;

        if current == goalIdx
            found = true;
            break;
        end

        openMask(current) = false;
        closed(current)   = true;
        [cr, cc] = ind2sub(sz, current);

        for m = 1:size(moves, 1)
            nr = cr + moves(m,1);
            nc = cc + moves(m,2);

            % Bounds and obstacle checks
            if nr < 1 || nr > rows || nc < 1 || nc > cols, continue; end
            if map(nr, nc), continue; end

            % Prevent cutting corners on diagonal moves
            if moves(m,1) ~= 0 && moves(m,2) ~= 0
                if map(cr + moves(m,1), cc) || map(cr, cc + moves(m,2))
                    continue;
                end
            end

            nIdx = sub2ind(sz, nr, nc);
            if closed(nIdx), continue; end

            % Cost of moving into the neighbour = step length x its node weight
            tentativeG = g(current) + stepCost(m) * nodeWeight(nIdx);
            if tentativeG < g(nIdx)
                parent(nIdx)   = current;
                g(nIdx)        = tentativeG;
                f(nIdx)        = tentativeG + hScale * heuristic([nr nc], goal, allowDiagonal);
                openMask(nIdx) = true;
            end
        end
    end

    if ~found
        path = [];
        cost = Inf;
        return;
    end

    % Reconstruct the path by walking back through parents
    cost = g(goalIdx);
    idx  = goalIdx;
    list = idx;
    while idx ~= startIdx
        idx  = parent(idx);
        list = [idx; list]; %#ok<AGROW>
    end
    [pr, pc] = ind2sub(sz, list);
    path = [pr, pc];
end

function route = buildRouteList(path, sz, nodeWeight)
% Turn an N-by-2 [row, col] path into a table of the nodes it travels through.
% Columns:
%   Step       - hop number (0 = start)
%   NodeID     - linear index of the cell in the map (unique node ID)
%   GridRow, GridCol - grid position ('Row' is reserved by MATLAB tables)
%   Move       - heading taken to arrive at this node (N, NE, E, ... ; START)
%   StepCost   - cost of the hop into this node (1 or sqrt(2))
%   CumCost    - total cost from the start to this node
%   IsWaypoint - true at start, goal and every node where the heading changes

    n      = size(path, 1);
    nodeID = sub2ind(sz, path(:,1), path(:,2));

    d        = [0 0; diff(path)];          % [dRow dCol] into each node
    if nargin < 3 || isempty(nodeWeight)
        nodeWeight = ones(sz);
    end
    weight   = nodeWeight(nodeID);
    stepLen  = sqrt(sum(d.^2, 2));         % 1 for straight, sqrt(2) for diagonal
    stepCost = stepLen .* weight;          % weighted cost of the hop into each node
    cumCost  = cumsum(stepCost);

    % Row decreasing = North (up on the plot), column increasing = East
    names = {'NW','N','NE'; 'W','','E'; 'SW','S','SE'};
    move  = cell(n, 1);
    move{1} = 'START';
    for i = 2:n
        move{i} = names{d(i,1) + 2, d(i,2) + 2};
    end

    isWaypoint = false(n, 1);
    isWaypoint([1 n]) = true;
    for i = 2:n-1
        if any(d(i,:) ~= d(i+1,:))         % heading changes after this node
            isWaypoint(i) = true;
        end
    end

    route = table((0:n-1)', nodeID, path(:,1), path(:,2), move, weight, ...
                  stepCost, cumCost, isWaypoint, ...
                  'VariableNames', {'Step','NodeID','GridRow','GridCol','Move', ...
                                    'Weight','StepCost','CumCost','IsWaypoint'});
end

function [hexStr, bytes] = routeToHex(nodeIDs, bytesPerNode) %#ok<*DEFNU>
% (Older grid-cell method, no longer called; the SDR bank uses routeToSdrMask.)
% Encode an ordered list of node IDs as a hex string.
% Byte layout (big-endian, bytesPerNode bytes per field):
%   [ hop count N ][ node 1 ][ node 2 ] ... [ node N ][ checksum (1 byte) ]
% The checksum is the XOR of every byte before it.
%   bytesPerNode = 1 (default): node IDs 0..255,   route up to 255 nodes
%   bytesPerNode = 2:           node IDs 0..65535, route up to 65535 nodes
% Example, nodes [135 187 239]:
%   1 byte : '0387BBEF' + checksum -> '0387BBEFD0'
%   2 bytes: '0003008700BB00EFD0'
%   hexStr - character row vector
%   bytes  - the same data as a uint8 row vector (ready to transmit)

    if nargin < 2 || isempty(bytesPerNode)
        bytesPerNode = 1;
    end
    maxVal = 256^bytesPerNode - 1;

    nodeIDs = double(nodeIDs(:));
    n = numel(nodeIDs);
    if any(nodeIDs < 0 | nodeIDs > maxVal | nodeIDs ~= round(nodeIDs))
        error('Node IDs must be integers from 0 to %d to fit in %d byte(s).', ...
              maxVal, bytesPerNode);
    end
    if n > maxVal
        error('Route too long: %d nodes (maximum %d).', n, maxVal);
    end

    vals = [n; nodeIDs];                     % hop count, then the nodes
    b = zeros(numel(vals), bytesPerNode);
    for j = 1:bytesPerNode                   % split each value into bytes, high byte first
        b(:, j) = mod(floor(vals / 256^(bytesPerNode - j)), 256);
    end
    b = reshape(b', 1, []);

    checksum = 0;
    for k = 1:numel(b)
        checksum = bitxor(checksum, b(k));
    end

    bytes  = uint8([b, checksum]);
    hexStr = reshape(dec2hex(bytes, 2)', 1, []);
end

function nodeIDs = hexToRoute(hexStr, bytesPerNode)
% Decode a hex string made by routeToHex back into a column of node IDs.
% bytesPerNode must match the value used to encode (default 1).
% Errors if the length or checksum is wrong (e.g. a corrupted packet).

    if nargin < 2 || isempty(bytesPerNode)
        bytesPerNode = 1;
    end

    hexStr = regexprep(char(hexStr), '\s', '');      % ignore any spaces
    if mod(numel(hexStr), 2) ~= 0 || numel(hexStr) < 2 * (bytesPerNode + 1)
        error('Hex route string has an invalid length.');
    end
    b = hex2dec(reshape(hexStr, 2, [])')';           % bytes as doubles

    checksum = 0;
    for k = 1:numel(b)
        checksum = bitxor(checksum, b(k));           % XOR of all bytes incl. checksum
    end
    if checksum ~= 0
        error('Hex route checksum failed: data is corrupted.');
    end

    body = b(1:end-1);                               % drop the checksum byte
    if mod(numel(body), bytesPerNode) ~= 0
        error('Hex route length does not match %d byte(s) per node.', bytesPerNode);
    end
    fields = reshape(body, bytesPerNode, [])';       % one row per value
    vals   = fields * (256 .^ (bytesPerNode-1:-1:0))';

    n = vals(1);                                     % hop count
    if numel(vals) - 1 ~= n
        error('Hex route says %d nodes but contains %d.', n, numel(vals) - 1);
    end
    nodeIDs = vals(2:end);
end

function drawGrid(ax, rows, cols)
% Light grid lines between cells.
    gc = [0.85 0.85 0.85];
    for r = 0.5:1:rows+0.5, plot(ax, [0.5 cols+0.5], [r r], 'Color', gc); end
    for c = 0.5:1:cols+0.5, plot(ax, [c c], [0.5 rows+0.5], 'Color', gc); end
end

function drawPathOverlay(ax, path, waypoints, start, goal)
% Path (red), numbered waypoints (yellow), start (green) and goal (magenta).
    if ~isempty(path)
        plot(ax, path(:,2), path(:,1), 'r-', 'LineWidth', 2.5);
        plot(ax, waypoints.GridCol, waypoints.GridRow, 'ko', ...
             'MarkerSize', 6, 'MarkerFaceColor', 'y');
        for k = 1:height(waypoints)
            text(ax, waypoints.GridCol(k) + 0.6, waypoints.GridRow(k) - 0.6, ...
                 num2str(k), 'FontSize', 9, 'FontWeight', 'bold', 'Color', [0.6 0 0]);
        end
    end
    plot(ax, start(2), start(1), 'go', 'MarkerSize', 10, 'MarkerFaceColor', 'g');
    plot(ax, goal(2),  goal(1),  'mp', 'MarkerSize', 14, 'MarkerFaceColor', 'm');
end

function h = heuristic(a, b, allowDiagonal)
% Octile distance for 8-connected grids, Manhattan for 4-connected.
    dr = abs(a(1) - b(1));
    dc = abs(a(2) - b(2));
    if allowDiagonal
        h = (dr + dc) + (sqrt(2) - 2) * min(dr, dc);
    else
        h = dr + dc;
    end
end
