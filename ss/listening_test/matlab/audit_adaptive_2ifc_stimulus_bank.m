function audit = audit_adaptive_2ifc_stimulus_bank(manifestPath, publicRoot)
%AUDIT_ADAPTIVE_2IFC_STIMULUS_BANK Verify adaptive manifest and WAV assets.

    arguments
        manifestPath (1, 1) string
        publicRoot (1, 1) string
    end

    assert(isfile(manifestPath), "Adaptive manifest not found: %s", manifestPath);
    manifest = jsondecode(fileread(manifestPath));
    assert(isfield(manifest, "mode") && string(manifest.mode) == "adaptive", ...
        "Manifest is not an adaptive listening-test manifest.");
    assert(isfield(manifest, "blocks") && ~isempty(manifest.blocks), ...
        "Adaptive manifest contains no blocks.");

    blocks = manifest.blocks;
    if ~isstruct(blocks)
        error("Adaptive manifest blocks are malformed.");
    end
    blocks = blocks(:);

    trackRows = repmat(empty_track_row(), 0, 1);
    missingFiles = strings(0, 1);

    for iBlock = 1:numel(blocks)
        block = blocks(iBlock);
        assert(isfield(block, "adaptive") && block.adaptive, ...
            "Block %d is not marked adaptive.", iBlock);
        assert(isfield(block, "tracks") && ~isempty(block.tracks), ...
            "Adaptive block %d contains no tracks.", iBlock);

        tracks = block.tracks(:);
        for iTrack = 1:numel(tracks)
            track = tracks(iTrack);
            levels = track.levels(:);
            separations = [levels.separationDeg].';
            assert(numel(levels) >= 3, ...
                "Adaptive track %s contains too few levels.", string(track.trackId));
            assert(all(isfinite(separations)) && all(separations > 0), ...
                "Adaptive track %s has invalid separation values.", string(track.trackId));
            assert(issorted(separations, "descend"), ...
                "Adaptive track %s levels must be ordered easy-to-hard.", ...
                string(track.trackId));

            for iLevel = 1:numel(levels)
                for stimulusName = ["standard", "target", "targetOpposite"]
                    assert(isfield(levels(iLevel).stimuli, stimulusName), ...
                        "Adaptive level %s/%d lacks %s stimulus.", ...
                        string(track.trackId), iLevel, stimulusName);
                    url = string(levels(iLevel).stimuli.(stimulusName).url);
                    wavPath = fullfile(publicRoot, strrep(url, "/", filesep));
                    if ~isfile(wavPath)
                        missingFiles(end + 1, 1) = wavPath; %#ok<AGROW>
                    else
                        info = audioinfo(wavPath);
                        assert(info.NumChannels == 2, ...
                            "Adaptive WAV is not stereo: %s", wavPath);
                        assert(info.SampleRate == 48000, ...
                            "Adaptive WAV is not 48 kHz: %s", wavPath);
                    end
                end
            end

            row = empty_track_row();
            row.blockId = string(block.blockId);
            row.axis = string(block.axis);
            row.trackId = string(track.trackId);
            row.method = string(track.method);
            row.retainedDirections = double(track.retainedDirections);
            row.virtualHrtfSubjectId = double(track.virtualHrtfSubjectId);
            row.levelCount = numel(levels);
            row.maxSeparationDeg = max(separations);
            row.minSeparationDeg = min(separations);
            trackRows(end + 1, 1) = row; %#ok<AGROW>
        end
    end

    assert(isempty(missingFiles), "Adaptive manifest references missing WAVs:\n%s", ...
        strjoin(missingFiles, newline));

    audit = struct2table(trackRows);
    fprintf("Adaptive listening bank audit passed: %d tracks, %d levels.\n", ...
        height(audit), sum(audit.levelCount));

end

function row = empty_track_row()
    row = struct("blockId", "", "axis", "", "trackId", "", ...
        "method", "", "retainedDirections", NaN, ...
        "virtualHrtfSubjectId", NaN, "levelCount", NaN, ...
        "maxSeparationDeg", NaN, "minSeparationDeg", NaN);
end
