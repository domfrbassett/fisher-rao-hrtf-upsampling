function y = rms(x, varargin)
%RMS Compatibility adapter for AMT 1.6 barumerli2023 on recent MATLAB.
% Supports AMT's rms(x,'dim',n) and the bundled LTFAT 'ac'/'noac' flags.

    dimension = [];
    removeMean = false;
    index = 1;

    while index <= numel(varargin)
        argument = varargin{index};
        if isnumeric(argument) && isscalar(argument)
            dimension = argument;
            index = index + 1;
            continue;
        end

        argument = lower(string(argument));
        switch argument
            case "dim"
                assert(index < numel(varargin), ...
                    "The 'dim' option requires a dimension value.");
                dimension = varargin{index + 1};
                index = index + 2;
            case "ac"
                removeMean = true;
                index = index + 1;
            case "noac"
                index = index + 1;
            otherwise
                error("Unsupported rms compatibility signature.");
        end
    end

    if isempty(dimension)
        dimension = find(size(x) ~= 1, 1, "first");
        if isempty(dimension)
            dimension = 1;
        end
    end

    if removeMean
        x = x - mean(x, dimension);
    end
    y = sqrt(mean(abs(x) .^ 2, dimension));

end
