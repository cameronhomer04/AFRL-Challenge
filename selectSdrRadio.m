function radio = selectSdrRadio(radios, platform, n)
% SELECTSDRRADIO  Pick one radio from the list made by findSdrRadios.
%
%   radio = selectSdrRadio(radios, platform)
%   radio = selectSdrRadio(radios, platform, n)
%
%   radios   - struct array from findSdrRadios
%   platform - 'B210', 'X310' or 'any'
%   n        - (optional) which one of that platform to take, default 1
%
% Example: two radios, B210 transmits and X310 receives
%   txRadio = selectSdrRadio(radios, 'B210');
%   rxRadio = selectSdrRadio(radios, 'X310');

    if nargin < 3, n = 1; end

    if strcmpi(platform, 'any')
        match = radios;
    else
        match = radios(strcmpi({radios.Platform}, platform));
    end

    if numel(match) < n
        error('Asked for %s number %d but only %d found.', upper(platform), n, numel(match));
    end
    radio = match(n);
end
