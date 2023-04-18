classdef soundObject

    properties
        folder                      char
        ID                          char
        uploader                    char
        fname                       char
        dat                         double
        Ns                  (1,1)   double          {mustBePositive} = 1
        fs                  (1,1)   double          {mustBePositive} = 1
        ts                          double          {mustBeNonnegative}
        player                      audioplayer
        spect                       ShortTimeFourierTransform
    end

    methods

        function obj = soundObject(folderName, varargin)

            if nargin == 0      % used for object vectorizing

            elseif nargin == 1  % default construct with folderName argument

                currentDir = dir;

                % checking existance of folderName within current folder
                if any(strcmp(string({currentDir([currentDir.isdir]).name}), folderName))

                    fileNames = dir(folderName);

                    %% main constructor loop
                    if numel(fileNames) == 2 % only consist . and .. items

                        disp('Empty folder!');

                    else % not empty folder

                        % audio files numbers
                        afn = find([0 0 endsWith(string({fileNames(~[fileNames.isdir]).name}), ...
                            {'.wav', '.aiff', '.aifc', '.aif', '.au', '.ogg', '.opus', '.flac', '.mp3', '.mp4', '.m4a'})]); % all files ending with audio sufixes except . and ..

                        obj(numel(afn), 1) = obj();             % vectorizing object (calling obj without arguments)
                        index = 0;                              % init index

                        for audioElement = afn                  % for all audio files within folder

                            index = index + 1;                  % current element index
                            splitStr = regexp(fileNames(audioElement).name,'\__','split');      % breaking file name to ID, user and file name

                            obj(index, 1).folder = folderName;

                            % strips metadata from RAW filename
                            obj(index, 1) = name2ID(obj(index, 1), splitStr);

                            % load an audio data files
                            [obj(index, 1).dat, obj(index, 1).fs] = audioread([folderName, filesep, fileNames(audioElement).name]);

                            obj(index, 1).Ns = size(obj(index, 1).dat,1);                       % number of samples - signal length
                            obj(index, 1).ts = ((0:obj(index, 1).Ns - 1) / obj(index, 1).fs)';  % time steps vector

                            % normalization
                            obj(index, 1).dat = obj(index, 1).dat./max(abs(obj(index, 1).dat));

                            % adding player
                            obj(index, 1).player = audioplayer(obj(index, 1).dat(:,1), obj(index, 1).fs);

                            % create spectrogram
                            obj(index, 1) = createSpectrogram(obj(index, 1));

                        end
                    end
                end

            elseif nargin == 2 && string(varargin{1}) == "plot" % construct with plot (under construction)

                obj = soundObject(folderName); % construct
                disp('obj(xxxx).plotSpectrogram ... ');
            else

                % unused cases
                disp('too many arguments')
            end

        end % construct

    end % methods

    methods (Access = public)

        function plotSpectrogram(obj)

            for index = 1:numel(obj)

                sdB = mag2db(abs(obj(index).spect.s));                  % magnitude to decibels (dB)
                cbR = max(sdB(:)) + [-60 0];                            % seting colorbar range

                Fig = soundObject.initFig(obj(index).fname);            % init figures

                % mesh spectrogram
                mesh(obj(index).spect.t, obj(index).spect.f(obj(index).spect.f >= 0), sdB(obj(index).spect.f >= 0, :, 1), 'EdgeColor', 'none', 'FaceColor', 'interp');

                set(gca, 'YScale', 'log', 'CLim', cbR, 'Xlim', [obj(index).spect.t(1) obj(index).spect.t(end)], 'Ylim', [0 obj(index).spect.f(end)], 'YTick', 2.^(1:20));

                title([obj(index).fname, ' with length of ', num2str(obj(index).ts(end), '%.2f'), 's. Sampling frequency ', num2str(obj(index).fs, '%.0f'), 'Hz.'], 'interpreter', 'none', 'FontSize', 16);

                subtitle(['Power spectrogram with windowSize of ', num2str(obj(index).spect.windowSize, '%.0f'), ' and FFTSize of ', num2str(obj(index).spect.FFTSize, '%.0f'),'.'], 'FontSize', 14);

                xlabel('Time [s]', 'FontSize', 16);
                ylabel('Frequency [Hz]', 'FontSize', 16);

                view(2)
                % colormap hot
                CB = colorbar;
                CB.Label.String = 'Magnitude [dB]';
                CB.FontSize = 16;

                if ~isempty(obj(index).ID) && ~isempty(obj(index).uploader)

                    exportgraphics(Fig, [obj(index).folder, filesep, obj(index).ID, '__', obj(index).uploader, ...
                        '__', extractBefore(obj(index).fname, '.'), '.pdf'], 'BackgroundColor','white','ContentType','image');
                else
                    exportgraphics(Fig, [obj(index).folder, filesep, extractBefore(obj(index).fname, '.'), '.pdf'], ...
                        'BackgroundColor','white','ContentType','image');
                end
                close(Fig);
            end
        end % plotSpectrogram

    end % (Access = public)

    methods (Access = private)

        function obj = createSpectrogram(obj)

            % Short-time Fourier transform
            % [s, f, t] = spectrogram(x(:,1), ...
            % hann(windowLength, "periodic"), windowLength*.75,
            % ... FFTLength, fs, "centered"); % identical results from stft and spectrogram

            obj.spect = ShortTimeFourierTransform;

            % https://support.ircam.fr/docs/AudioSculpt/3.0/co/Window%20Size.html

            fsignal = 25;              % signal frequency

            % The window size influences the temporal or frequency resolution, or precision of the representation of the signal.

            obj.spect.windowSize = 2^nextpow2(5 * obj.fs / fsignal); % the lower the pitch, the bigger the window size should be.

            numberOfBins = obj.spect.windowSize / 2;

            % The spectrum is equally split into numberOfBins with frequency resolution (FR) Hz width each.
            % The higher frequency resolution is more precise.
            % oversampling factor (fs) improves the frequency resolution of the analysis
            % oversampling of the window step improves its temporal resolution.

            fMax = obj.fs / 2;              % Nyquist frequency

            % good frequency resolution about 20Hz, bad frequency resolution > 80Hz
            FR = fMax/numberOfBins;     % frequency resolution is the frequency band of a bin
            %FR = fs/obj.spect.windowSize;        % frequency resolution is the frequency band of a bin

            f0 = 5 * obj.fs / obj.spect.windowSize;   % lowest detectable frequency

            % Increasing the Frequency Resolution with the FFT Size
            % With an oversampling rate of 2, we have twice more bins in the window,
            % and the frequency resolution is twice more precise.
            obj.spect.FFTSize       = 2 * obj.spect.windowSize;

            % Short-time Fourier transform
            [obj.spect.s, obj.spect.f, obj.spect.t] = stft(obj.dat, obj.fs, ...
                'FrequencyRange', "onesided", Window = hann(obj.spect.windowSize, "periodic"), ...
                OverlapLength = .5 * obj.spect.windowSize, FFTLength = obj.spect.FFTSize);

        end % createSpectrogram

        % strips metadata from RAW filename
        function obj = name2ID(obj, param)

            if numel(param) == 3
                obj.ID        = param{1};                              % ID
                obj.uploader  = param{2};                              % uploader
                obj.fname     = param{3};                              % file name
            else
                obj.fname     = param{1};                              % file name
            end

        end

    end % (Access = private)

    methods (Static)

        function Fig = initFig(name)

            Fig.fontname = 'Arial';
            Fig = figure('DefaultTextFontName', Fig.fontname, 'DefaultAxesFontName', Fig.fontname);

            if size(groot().MonitorPositions, 1) == 2
                set(gcf, 'Position', [0 0 1 1], 'units', 'normalized', 'outerposition', [1 0 1 1]);  % figure on the second monitor full screen
            else
                set(gcf, 'Position', [0 0 1 1], 'units', 'normalized', 'outerposition', [0 0 1 1]);  % figure on the only monitor full screen
            end
            set(Fig, 'Name', ['Spectrogram of ', name], 'NumberTitle', 'off', 'Color', 'white');
            %set(Fig, 'Renderer', 'painters');           % renderer for vector graphics
            set(Fig, 'Renderer', 'opengl');             % renderer for raster graphics

        end % initFig

    end % (Static)


end % classdef