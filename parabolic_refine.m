function f_peak = parabolic_refine(f_axis, p_db, k)
% Sub-bin peak frequency via 3-point parabolic fit.

    n = numel(p_db);

    % Can't fit a 3-point parabola at the array edge -- no neighbor on
    % one side. Fall back to the raw bin frequency.
    if k == 1 || k == n
        f_peak = f_axis(k);
        return;
    end

    y0 = p_db(k - 1);
    y1 = p_db(k);
    y2 = p_db(k + 1);

    % Discrete second derivative -- curvature of the 3-point parabola.
    denom = y0 - 2*y1 + y2;

    % Degenerate (collinear) case: no single vertex, fall back.
    if denom == 0
        f_peak = f_axis(k);
        return;
    end

    % Vertex offset in fractional bins from k. Asymmetry (y0 - y2) sets
    % the sign and magnitude; curvature in the denominator scales it.
    delta = 0.5 * (y0 - y2) / denom;

    % Numerical safety net -- true peak is within half a bin of k.
    delta = max(min(delta, 0.5), -0.5);

    bin_width = f_axis(2) - f_axis(1);
    f_peak = f_axis(k) + delta * bin_width;
end
