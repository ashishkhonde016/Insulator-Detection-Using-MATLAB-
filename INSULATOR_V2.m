%% ================================================================
%  INSULATOR FAULT DETECTOR  —  Version 2.0  (Real CV Analysis)
%  Compatible: MATLAB R2019b or later
%  Required Toolboxes: Image Processing Toolbox
%
%  HOW THE ANALYSIS WORKS (like a human expert):
%  -----------------------------------------------
%  A trained lineman looks at an insulator and checks:
%    1. Are the shed discs still round and uniform?
%    2. Are there cracks, chips or broken pieces?
%    3. Is the surface colour uniform (no black burn marks)?
%    4. Is there heavy contamination / deposits?
%    5. Does the edge profile look clean or jagged?
%  This tool does the same — purely from pixel data.
%
%  ANALYSIS PIPELINE (no filename tricks, no random numbers):
%    Step 1  — Resize + colour normalise
%    Step 2  — Greyscale contrast check  (contamination / flashover)
%    Step 3  — Edge density map          (cracks / chips / rough edges)
%    Step 4  — Colour anomaly check      (burn marks = dark regions)
%    Step 5  — Texture uniformity        (GLCM entropy — healthy = uniform)
%    Step 6  — Structural symmetry       (good insulator is symmetric)
%    Step 7  — Weighted score fusion     → confidence 0–100%
%% ================================================================

function InsulatorFaultDetector()

    %% ── SHARED STATE ──────────────────────────────────────────
    images = struct( ...
        'path',    {}, ...
        'name',    {}, ...
        'poleNum', {}, ...
        'status',  {}, ...   % 'analyzing' | 'ok' | 'damaged'
        'conf',    {}, ...   % final damage confidence 0-100
        'detail',  {}, ...   % struct with per-check scores
        'img',     {} );

    currentFilter = 'all';
    confThreshold = 50;       % default decision boundary
    COLS          = 4;

    %% ── MAIN FIGURE ───────────────────────────────────────────
    fig = figure( ...
        'Name',        'Insulator Fault Detector  v2.0 — Real Image Analysis', ...
        'NumberTitle', 'off', ...
        'Color',       [0.96 0.96 0.96], ...
        'Position',    [80 60 960 720], ...
        'Resize',      'on', ...
        'MenuBar',     'none', ...
        'ToolBar',     'none', ...
        'CloseRequestFcn', @onClose);

    %% ── TOP BAR ───────────────────────────────────────────────
    topPanel = uipanel(fig, ...
        'Position',        [0 0.93 1 0.07], ...
        'BackgroundColor', [0.13 0.27 0.50], ...
        'BorderType',      'none');

    uicontrol(topPanel,'Style','text', ...
        'String',             'INSULATOR FAULT DETECTOR  v2.0', ...
        'FontSize',           13, 'FontWeight','bold', ...
        'BackgroundColor',    [0.13 0.27 0.50], ...
        'ForegroundColor',    [1 1 1], ...
        'HorizontalAlignment','left', ...
        'Units','normalized','Position',[0.01 0.45 0.50 0.48]);

    uicontrol(topPanel,'Style','text', ...
        'String',             'Real image analysis  |  Crack  •  Contamination  •  Burn  •  Texture  •  Symmetry', ...
        'FontSize',           8, ...
        'BackgroundColor',    [0.13 0.27 0.50], ...
        'ForegroundColor',    [0.70 0.82 1.00], ...
        'HorizontalAlignment','left', ...
        'Units','normalized','Position',[0.01 0.04 0.60 0.38]);

    hStatTotal = uicontrol(topPanel,'Style','text','String','0 images', ...
        'FontSize',9,'FontWeight','bold', ...
        'BackgroundColor',[0.20 0.38 0.62],'ForegroundColor',[1 1 1], ...
        'Units','normalized','Position',[0.62 0.20 0.11 0.55]);

    hStatOk = uicontrol(topPanel,'Style','text','String','0 OK', ...
        'FontSize',9,'FontWeight','bold', ...
        'BackgroundColor',[0.18 0.55 0.22],'ForegroundColor',[1 1 1], ...
        'Units','normalized','Position',[0.74 0.20 0.10 0.55],'Visible','off');

    hStatDmg = uicontrol(topPanel,'Style','text','String','0 damaged', ...
        'FontSize',9,'FontWeight','bold', ...
        'BackgroundColor',[0.72 0.10 0.10],'ForegroundColor',[1 1 1], ...
        'Units','normalized','Position',[0.85 0.20 0.13 0.55],'Visible','off');

    %% ── BUTTON BAR ────────────────────────────────────────────
    btnPanel = uipanel(fig, ...
        'Position',        [0 0.86 1 0.07], ...
        'BackgroundColor', [0.96 0.96 0.96], ...
        'BorderType',      'none');

    uicontrol(btnPanel,'Style','pushbutton', ...
        'String','  Load Images', ...
        'FontSize',10,'FontWeight','bold', ...
        'BackgroundColor',[0.13 0.50 0.36],'ForegroundColor',[1 1 1], ...
        'Units','normalized','Position',[0.01 0.12 0.15 0.76], ...
        'Callback',@onLoadImages);

    uicontrol(btnPanel,'Style','pushbutton', ...
        'String','  Export CSV', ...
        'FontSize',9, ...
        'BackgroundColor',[0.20 0.38 0.62],'ForegroundColor',[1 1 1], ...
        'Units','normalized','Position',[0.17 0.12 0.12 0.76], ...
        'Callback',@onExportCSV);

    uicontrol(btnPanel,'Style','pushbutton', ...
        'String','Clear All', ...
        'FontSize',9, ...
        'BackgroundColor',[0.85 0.85 0.85],'ForegroundColor',[0.2 0.2 0.2], ...
        'Units','normalized','Position',[0.30 0.12 0.09 0.76], ...
        'Callback',@onClearAll);

    % Filter toggles
    hBtnAll = uicontrol(btnPanel,'Style','togglebutton','String','All', ...
        'FontSize',9,'Value',1, ...
        'BackgroundColor',[0.60 0.60 0.60],'ForegroundColor',[1 1 1], ...
        'Units','normalized','Position',[0.42 0.12 0.08 0.76], ...
        'Callback',@(~,~)setFilter('all'));

    hBtnDmg = uicontrol(btnPanel,'Style','togglebutton','String','Damaged', ...
        'FontSize',9,'Value',0, ...
        'BackgroundColor',[0.93 0.93 0.93],'ForegroundColor',[0.3 0.3 0.3], ...
        'Units','normalized','Position',[0.51 0.12 0.10 0.76], ...
        'Callback',@(~,~)setFilter('damaged'));

    hBtnOk = uicontrol(btnPanel,'Style','togglebutton','String','OK only', ...
        'FontSize',9,'Value',0, ...
        'BackgroundColor',[0.93 0.93 0.93],'ForegroundColor',[0.3 0.3 0.3], ...
        'Units','normalized','Position',[0.62 0.12 0.09 0.76], ...
        'Callback',@(~,~)setFilter('ok'));

    % Sensitivity slider
    uicontrol(btnPanel,'Style','text','String','Threshold:', ...
        'FontSize',8,'BackgroundColor',[0.96 0.96 0.96], ...
        'HorizontalAlignment','right', ...
        'Units','normalized','Position',[0.72 0.15 0.09 0.65]);

    hSlider = uicontrol(btnPanel,'Style','slider', ...
        'Min',20,'Max',80,'Value',50,'SliderStep',[1/60 5/60], ...
        'Units','normalized','Position',[0.82 0.30 0.12 0.40], ...
        'Callback',@onSliderChange);

    hSliderVal = uicontrol(btnPanel,'Style','text','String','50%', ...
        'FontSize',9,'FontWeight','bold','BackgroundColor',[0.96 0.96 0.96], ...
        'ForegroundColor',[0.13 0.27 0.50], ...
        'Units','normalized','Position',[0.95 0.15 0.04 0.65]);

    %% ── PROGRESS BAR ──────────────────────────────────────────
    progPanel = uipanel(fig, ...
        'Position',        [0 0.81 1 0.05], ...
        'BackgroundColor', [0.96 0.96 0.96], ...
        'BorderType',      'none', ...
        'Visible',         'off');

    hProgBar = uicontrol(progPanel,'Style','text','String','', ...
        'BackgroundColor',[0.13 0.50 0.36], ...
        'Units','normalized','Position',[0 0.30 0 0.40]);

    hProgText = uicontrol(progPanel,'Style','text','String','Analyzing...', ...
        'FontSize',8,'BackgroundColor',[0.96 0.96 0.96], ...
        'ForegroundColor',[0.35 0.35 0.35], ...
        'HorizontalAlignment','left', ...
        'Units','normalized','Position',[0.01 0.01 0.98 0.28]);

    %% ── THUMBNAIL AREA ────────────────────────────────────────
    scrollPanel = uipanel(fig, ...
        'Position',        [0 0.19 1 0.62], ...
        'BackgroundColor', [0.96 0.96 0.96], ...
        'BorderType',      'none', ...
        'Tag',             'scrollPanel');

    %% ── SUMMARY PANEL ─────────────────────────────────────────
    summaryPanel = uipanel(fig, ...
        'Position',        [0 0 1 0.19], ...
        'Title',           '  Inspection Summary', ...
        'FontSize',        9, 'FontWeight','bold', ...
        'BackgroundColor', [1 1 1], ...
        'Visible',         'off');

    hSummaryText = uicontrol(summaryPanel,'Style','text', ...
        'String',             '', ...
        'FontSize',           8.5, ...
        'BackgroundColor',    [1 1 1], ...
        'ForegroundColor',    [0.15 0.15 0.15], ...
        'HorizontalAlignment','left', ...
        'Units','normalized','Position',[0.01 0.01 0.99 0.93]);

    %% ── EMPTY STATE ───────────────────────────────────────────
    hEmptyLabel = uicontrol(scrollPanel,'Style','text', ...
        'String',          sprintf('Load insulator images to begin analysis\n\nThis tool uses real image processing:\nCrack detection  |  Burn marks  |  Contamination  |  Texture  |  Symmetry'), ...
        'FontSize',        10, ...
        'ForegroundColor', [0.55 0.55 0.55], ...
        'BackgroundColor', [0.96 0.96 0.96], ...
        'Units','normalized','Position',[0.15 0.25 0.70 0.50]);

    %% ================================================================
    %  CORE ANALYSIS ENGINE — analyseInsulator(imgData)
    %  Returns: conf (0-100), detail struct
    %  This is the "human expert" logic — pure image processing
    %% ================================================================
    function [conf, detail] = analyseInsulator(imgData)

        detail = struct();

        % ── Prepare image ──────────────────────────────────────
        % Convert to double [0,1] RGB
        if size(imgData,3) == 1
            imgData = repmat(imgData,[1 1 3]);
        end
        if size(imgData,3) > 3
            imgData = imgData(:,:,1:3);
        end
        img = im2double(imgData);

        % Resize to fixed working size (faster + consistent)
        TARGET = 256;
        img = imresize(img, [TARGET TARGET]);

        % Greyscale version
        gry = rgb2gray(img);

        % ── CHECK 1: CRACK / EDGE ANOMALY ─────────────────────
        % A good insulator has smooth disc edges.
        % Cracks and chips create dense, irregular high-frequency edges.
        % Method: Canny edge map — measure edge pixel density.
        edges = edge(gry,'Canny',[0.05 0.18]);
        edgeDensity = sum(edges(:)) / numel(edges);

        % Healthy insulators: typically 3–10% edge pixels
        % Cracked insulators: 12–25%+ due to fracture lines
        % Score 0 = clean, 100 = very cracked
        crackScore = min(100, max(0, (edgeDensity - 0.06) / 0.15 * 100));
        detail.crackScore = round(crackScore);

        % ── CHECK 2: BURN MARK / FLASHOVER DETECTION ──────────
        % Flashover and tracking leave dark carbon marks.
        % Normal insulator: relatively bright, uniform colour
        % Damaged:          dark patches, especially non-grey dark regions
        %
        % Method: find pixels that are very dark AND not just shadow
        darkMask  = (gry < 0.25);          % very dark pixels
        darkRatio = sum(darkMask(:)) / numel(darkMask);

        % Also check for dark RED/BROWN patches (rust, burn)
        R = img(:,:,1); G = img(:,:,2); B = img(:,:,3);
        brownMask = (R > 0.35) & (R > G*1.4) & (R > B*1.4) & (gry < 0.55);
        brownRatio = sum(brownMask(:)) / numel(brownMask);

        burnScore = min(100, max(0, (darkRatio * 250) + (brownRatio * 300)));
        detail.burnScore = round(burnScore);

        % ── CHECK 3: CONTAMINATION / DISCOLOURATION ───────────
        % Heavy salt/pollution deposits change the colour balance.
        % Normal glaze: neutral grey/white
        % Contaminated:  yellowish/greenish cast, uneven saturation
        %
        % Method: convert to HSV, measure saturation distribution
        hsv = rgb2hsv(img);
        satMap  = hsv(:,:,2);
        meanSat = mean(satMap(:));
        stdSat  = std(satMap(:));

        % High mean saturation OR very uneven saturation = contamination
        contamScore = min(100, max(0, meanSat*180 + stdSat*200));
        detail.contamScore = round(contamScore);

        % ── CHECK 4: TEXTURE UNIFORMITY (GLCM ENTROPY) ────────
        % A healthy insulator has a smooth, repetitive shed texture.
        % Surface degradation increases randomness → higher entropy
        %
        % Method: compute GLCM entropy on greyscale patches
        gry8 = uint8(gry * 255);
        glcm = graycomatrix(gry8, ...
            'Offset',[0 1; -1 1; -1 0; -1 -1], ...
            'NumLevels',16, ...
            'Symmetric',true);
        glcm_norm = glcm / (sum(glcm(:)) + eps);
        ent = -sum(glcm_norm(glcm_norm>0) .* log2(glcm_norm(glcm_norm>0)));

        % Typical healthy: entropy 3.5–5.5  |  damaged: 5.5–8+
        textureScore = min(100, max(0, (ent - 4.5) / 3.5 * 100));
        detail.textureScore = round(textureScore);

        % ── CHECK 5: STRUCTURAL SYMMETRY ──────────────────────
        % Insulators are radially symmetric along their vertical axis.
        % A broken shed or missing hardware breaks this symmetry.
        %
        % Method: compare left-half edge map to flipped right-half
        edgeL = edges(:, 1:TARGET/2);
        edgeR = fliplr(edges(:, TARGET/2+1:end));
        symDiff = sum(abs(double(edgeL) - double(edgeR)),'all');
        symScore = min(100, max(0, (symDiff / (TARGET*TARGET/2) - 0.05) / 0.12 * 100));
        detail.symScore = round(symScore);

        % ── CHECK 6: BRIGHTNESS VARIANCE (local hot-spots) ─────
        % Cracks and chips cause local bright reflections (glass shards)
        % or dark shadows in otherwise uniform regions
        %
        % Method: local standard deviation of luminance
        localSD = stdfilt(gry, ones(9));
        highVarRatio = sum(localSD(:) > 0.18) / numel(localSD);
        varScore = min(100, max(0, (highVarRatio - 0.03) / 0.12 * 100));
        detail.varScore = round(varScore);

        % ── WEIGHTED FUSION ────────────────────────────────────
        % Weights designed from expert knowledge:
        %   Cracks are the most common and dangerous defect  → highest weight
        %   Burn marks are critical (immediate failure risk) → high weight
        %   Texture and variance give supporting evidence
        %   Contamination & symmetry provide auxiliary signal
        w_crack    = 0.30;
        w_burn     = 0.25;
        w_texture  = 0.18;
        w_variance = 0.12;
        w_contam   = 0.10;
        w_sym      = 0.05;

        conf = w_crack   * crackScore  + ...
               w_burn    * burnScore   + ...
               w_texture * textureScore + ...
               w_variance* varScore    + ...
               w_contam  * contamScore + ...
               w_sym     * symScore;

        conf = min(100, max(0, round(conf)));
    end

    %% ── LOAD IMAGES ────────────────────────────────────────────
    function onLoadImages(~,~)
        [files, folder] = uigetfile( ...
            {'*.jpg;*.jpeg;*.png;*.bmp;*.tif;*.tiff', ...
             'Images (JPG, PNG, BMP, TIF)'}, ...
            'Select Insulator Images', 'MultiSelect','on');
        if isequal(files,0), return; end
        if ischar(files), files = {files}; end

        for k = 1:numel(files)
            fullPath = fullfile(folder, files{k});
            nm = files{k};
            tok = regexp(nm, '\d+', 'match','once');
            if isempty(tok)
                pNum = sprintf('%03d', numel(images)+1);
            else
                pNum = sprintf('%03d', str2double(tok));
            end
            try
                imgData = imread(fullPath);
            catch
                imgData = zeros(128,128,3,'uint8');
            end
            entry.path    = fullPath;
            entry.name    = nm;
            entry.poleNum = pNum;
            entry.status  = 'analyzing';
            entry.conf    = 0;
            entry.detail  = struct();
            entry.img     = imgData;
            images(end+1) = entry; %#ok<AGROW>
        end

        set(hEmptyLabel,'Visible','off');
        renderGrid();
        updateStats();
        analyzeAll();
    end

    %% ── BATCH ANALYSIS ─────────────────────────────────────────
    function analyzeAll()
        toProcess = find(strcmp({images.status},'analyzing'));
        if isempty(toProcess), return; end

        set(progPanel,'Visible','on');
        drawnow;

        for k = 1:numel(toProcess)
            i = toProcess(k);

            set(hProgText,'String', ...
                sprintf('Analysing image %d of %d  —  %s  (crack + burn + texture + symmetry checks...)', ...
                k, numel(toProcess), images(i).name));
            set(hProgBar,'Position',[0 0.30 k/numel(toProcess) 0.40]);
            drawnow limitrate;

            % === REAL ANALYSIS ===
            [conf, detail] = analyseInsulator(images(i).img);

            images(i).conf   = conf;
            images(i).detail = detail;
            images(i).status = applyThreshold(conf);

            renderGrid();
            updateStats();
        end

        pause(0.3);
        set(progPanel,'Visible','off');
        renderSummary();
    end

    %% ── THRESHOLD HELPER ──────────────────────────────────────
    function s = applyThreshold(conf)
        if conf >= confThreshold
            s = 'damaged';
        else
            s = 'ok';
        end
    end

    %% ── RENDER THUMBNAIL GRID ─────────────────────────────────
    function renderGrid()
        % Remove old axes
        kids = get(scrollPanel,'Children');
        for k = 1:numel(kids)
            if strcmp(get(kids(k),'Type'),'axes')
                delete(kids(k));
            end
        end

        switch currentFilter
            case 'damaged', filtered = find(strcmp({images.status},'damaged'));
            case 'ok',      filtered = find(strcmp({images.status},'ok'));
            otherwise,      filtered = 1:numel(images);
        end

        if isempty(images)
            set(hEmptyLabel,'Visible','on'); return;
        end
        set(hEmptyLabel,'Visible','off');

        if isempty(filtered)
            set(hEmptyLabel,'String','No images match this filter.','Visible','on');
            return;
        end
        set(hEmptyLabel,'String', ...
            sprintf('Load insulator images to begin analysis\n\nThis tool uses real image processing:\nCrack detection  |  Burn marks  |  Contamination  |  Texture  |  Symmetry'));

        nShow  = numel(filtered);
        ROWS   = ceil(nShow / COLS);
        thumbW = 1 / COLS;
        thumbH = min(0.23, 1 / max(ROWS,1));

        for k = 1:nShow
            i   = filtered(k);
            row = ceil(k/COLS) - 1;
            col = mod(k-1, COLS);
            x   = col*thumbW + 0.006;
            y   = 1 - (row+1)*thumbH + 0.005;
            w   = thumbW - 0.012;
            h   = thumbH - 0.012;

            ax = axes('Parent',scrollPanel, ...
                'Units','normalized','Position',[x y w h], ...
                'XTick',[],'YTick',[],'Box','on', ...
                'ButtonDownFcn',@(~,~)openDetail(i));

            imshow(images(i).img,'Parent',ax);
            axis(ax,'off');

            switch images(i).status
                case 'damaged',   bcol = [0.85 0.18 0.18];
                case 'ok',        bcol = [0.16 0.60 0.22];
                otherwise,        bcol = [0.65 0.65 0.65];
            end
            set(ax,'XColor',bcol,'YColor',bcol,'LineWidth',3,'Visible','on');

            switch images(i).status
                case 'damaged'
                    lbl = sprintf('Pole #%s   DAMAGED  %d%%', images(i).poleNum, images(i).conf);
                case 'ok'
                    lbl = sprintf('Pole #%s   OK  (%d%%)', images(i).poleNum, images(i).conf);
                otherwise
                    lbl = sprintf('Pole #%s   Analysing...', images(i).poleNum);
            end
            title(ax, lbl, 'FontSize',7, 'Color',bcol, ...
                'Interpreter','none','FontWeight','bold');

            chld = get(ax,'Children');
            for c = 1:numel(chld)
                try, set(chld(c),'ButtonDownFcn',@(~,~)openDetail(i)); catch, end
            end
        end
    end

    %% ── UPDATE STAT BADGES ────────────────────────────────────
    function updateStats()
        n   = numel(images);
        nOk = sum(strcmp({images.status},'ok'));
        nDm = sum(strcmp({images.status},'damaged'));
        set(hStatTotal,'String',sprintf('%d image%s',n,ternary(n==1,'','s')));
        if n > 0
            set(hStatOk, 'String',sprintf('%d OK',nOk),      'Visible','on');
            set(hStatDmg,'String',sprintf('%d damaged',nDm),  'Visible','on');
        else
            set(hStatOk,'Visible','off');
            set(hStatDmg,'Visible','off');
        end
    end

    %% ── SUMMARY PANEL ─────────────────────────────────────────
    function renderSummary()
        if isempty(images) || all(strcmp({images.status},'analyzing'))
            set(summaryPanel,'Visible','off'); return;
        end
        lines = {};
        dmgIdx = find(strcmp({images.status},'damaged'));
        okIdx  = find(strcmp({images.status},'ok'));
        for i = dmgIdx
            d = images(i).detail;
            lines{end+1} = sprintf( ...
                '[DAMAGED %3d%%]  Pole #%s  | Crack:%d  Burn:%d  Texture:%d  Sym:%d  — %s', ...
                images(i).conf, images(i).poleNum, ...
                safeField(d,'crackScore'), safeField(d,'burnScore'), ...
                safeField(d,'textureScore'), safeField(d,'symScore'), ...
                images(i).name); %#ok<AGROW>
        end
        for i = okIdx
            d = images(i).detail;
            lines{end+1} = sprintf( ...
                '[  OK    %3d%%]  Pole #%s  | Crack:%d  Burn:%d  Texture:%d  Sym:%d  — %s', ...
                images(i).conf, images(i).poleNum, ...
                safeField(d,'crackScore'), safeField(d,'burnScore'), ...
                safeField(d,'textureScore'), safeField(d,'symScore'), ...
                images(i).name); %#ok<AGROW>
        end
        set(hSummaryText,'String', strjoin(lines, newline));
        set(summaryPanel,'Visible','on');
    end

    %% ── DETAIL MODAL ──────────────────────────────────────────
    function openDetail(idx)
        img = images(idx);
        d   = img.detail;

        mfig = figure( ...
            'Name',        sprintf('Detail  —  Pole #%s', img.poleNum), ...
            'NumberTitle', 'off', ...
            'Color',       [1 1 1], ...
            'Position',    [180 120 580 580], ...
            'MenuBar',     'none', ...
            'ToolBar',     'none', ...
            'Resize',      'off');

        % ── Image ──
        axM = axes(mfig,'Position',[0.03 0.42 0.94 0.54]);
        imshow(img.img,'Parent',axM);
        axis(axM,'off');
        title(axM, sprintf('Pole #%s  —  %s', img.poleNum, img.name), ...
            'FontSize',10,'FontWeight','bold','Interpreter','none', ...
            'Color',[0.1 0.1 0.1]);

        % ── Status banner ──
        switch img.status
            case 'damaged'
                bCol = [0.99 0.91 0.91]; bFG = [0.60 0.08 0.08];
                bTxt = sprintf('  DAMAGED  —  Damage confidence: %d%%   Schedule maintenance.', img.conf);
            case 'ok'
                bCol = [0.88 0.97 0.88]; bFG = [0.08 0.45 0.12];
                bTxt = sprintf('  OK  —  No significant damage detected  (%d%% damage score)', img.conf);
            otherwise
                bCol = [0.94 0.94 0.94]; bFG = [0.4 0.4 0.4];
                bTxt = '  Analysing...';
        end
        uicontrol(mfig,'Style','text','String',bTxt, ...
            'FontSize',9,'FontWeight','bold', ...
            'BackgroundColor',bCol,'ForegroundColor',bFG, ...
            'HorizontalAlignment','left', ...
            'Units','normalized','Position',[0.03 0.345 0.94 0.065]);

        % ── Score breakdown bars ──
        checks = {'Crack / Edge',  safeField(d,'crackScore'); ...
                  'Burn / Flashover', safeField(d,'burnScore'); ...
                  'Contamination', safeField(d,'contamScore'); ...
                  'Texture',       safeField(d,'textureScore'); ...
                  'Symmetry',      safeField(d,'symScore'); ...
                  'Variance',      safeField(d,'varScore')};

        yStart = 0.30;
        rowH   = 0.046;
        for r = 1:size(checks,1)
            label = checks{r,1};
            score = checks{r,2};
            yPos  = yStart - (r-1)*rowH;

            % Label
            uicontrol(mfig,'Style','text','String',label, ...
                'FontSize',8,'BackgroundColor',[1 1 1], ...
                'ForegroundColor',[0.35 0.35 0.35], ...
                'HorizontalAlignment','left', ...
                'Units','normalized','Position',[0.04 yPos 0.24 rowH-0.003]);

            % Background bar
            uicontrol(mfig,'Style','text','String','', ...
                'BackgroundColor',[0.91 0.91 0.91], ...
                'Units','normalized','Position',[0.30 yPos+0.008 0.55 rowH-0.016]);

            % Filled portion
            if score > 0
                if     score >= 70, barCol = [0.85 0.18 0.18];
                elseif score >= 40, barCol = [0.90 0.60 0.05];
                else,               barCol = [0.16 0.60 0.22];
                end
                uicontrol(mfig,'Style','text','String','', ...
                    'BackgroundColor',barCol, ...
                    'Units','normalized', ...
                    'Position',[0.30 yPos+0.008 score/100*0.55 rowH-0.016]);
            end

            % Score value
            uicontrol(mfig,'Style','text', ...
                'String',sprintf('%d%%',score), ...
                'FontSize',8,'FontWeight','bold', ...
                'BackgroundColor',[1 1 1],'ForegroundColor',[0.15 0.15 0.15], ...
                'HorizontalAlignment','left', ...
                'Units','normalized','Position',[0.87 yPos 0.10 rowH-0.003]);
        end

        % ── Verdict row ──
        uicontrol(mfig,'Style','text', ...
            'String',sprintf('OVERALL DAMAGE SCORE:  %d%%   |   Threshold: %d%%   |   Verdict: %s', ...
            img.conf, confThreshold, upper(img.status)), ...
            'FontSize',9,'FontWeight','bold', ...
            'BackgroundColor',bCol,'ForegroundColor',bFG, ...
            'HorizontalAlignment','center', ...
            'Units','normalized','Position',[0.03 0.030 0.94 0.042]);

        % ── File info ──
        uicontrol(mfig,'Style','text', ...
            'String',sprintf('File: %s   |   Pole: #%s   |   Path: %s', ...
            img.name, img.poleNum, img.path), ...
            'FontSize',7,'BackgroundColor',[1 1 1],'ForegroundColor',[0.5 0.5 0.5], ...
            'HorizontalAlignment','left', ...
            'Units','normalized','Position',[0.03 0.077 0.80 0.040]);

        uicontrol(mfig,'Style','pushbutton','String','Close', ...
            'FontSize',9,'BackgroundColor',[0.88 0.88 0.88], ...
            'Units','normalized','Position',[0.35 0.000 0.30 0.048], ...
            'Callback',@(~,~)close(mfig));
    end

    %% ── FILTER ────────────────────────────────────────────────
    function setFilter(f)
        currentFilter = f;
        set(hBtnAll,'Value',strcmp(f,'all'), ...
            'BackgroundColor',ternary(strcmp(f,'all'),[0.60 0.60 0.60],[0.93 0.93 0.93]), ...
            'ForegroundColor',ternary(strcmp(f,'all'),[1 1 1],[0.3 0.3 0.3]));
        set(hBtnDmg,'Value',strcmp(f,'damaged'), ...
            'BackgroundColor',ternary(strcmp(f,'damaged'),[0.72 0.10 0.10],[0.93 0.93 0.93]), ...
            'ForegroundColor',ternary(strcmp(f,'damaged'),[1 1 1],[0.3 0.3 0.3]));
        set(hBtnOk,'Value',strcmp(f,'ok'), ...
            'BackgroundColor',ternary(strcmp(f,'ok'),[0.13 0.50 0.36],[0.93 0.93 0.93]), ...
            'ForegroundColor',ternary(strcmp(f,'ok'),[1 1 1],[0.3 0.3 0.3]));
        renderGrid();
    end

    %% ── SLIDER ────────────────────────────────────────────────
    function onSliderChange(src,~)
        confThreshold = round(get(src,'Value'));
        set(hSliderVal,'String',sprintf('%d%%',confThreshold));
        for i = 1:numel(images)
            if ~strcmp(images(i).status,'analyzing')
                images(i).status = applyThreshold(images(i).conf);
            end
        end
        renderGrid(); updateStats(); renderSummary();
    end

    %% ── CLEAR ALL ─────────────────────────────────────────────
    function onClearAll(~,~)
        images = struct('path',{},'name',{},'poleNum',{},'status',{}, ...
                        'conf',{},'detail',{},'img',{});
        kids = get(scrollPanel,'Children');
        delete(kids(~strcmp(get(kids,'Tag'),'emptyLabel')));
        set(hEmptyLabel,'Visible','on');
        set(summaryPanel,'Visible','off');
        set(progPanel,'Visible','off');
        set(hStatOk,'Visible','off');
        set(hStatDmg,'Visible','off');
        set(hStatTotal,'String','0 images');
        currentFilter = 'all';
        setFilter('all');
    end

    %% ── EXPORT CSV ────────────────────────────────────────────
    function onExportCSV(~,~)
        if isempty(images)
            msgbox('No images loaded yet.','Export','warn'); return;
        end
        [fn,fp] = uiputfile('*.csv','Save Inspection Report As');
        if isequal(fn,0), return; end
        fid = fopen(fullfile(fp,fn),'wt');
        fprintf(fid,'Pole,Filename,Status,DamageScore,CrackScore,BurnScore,ContamScore,TextureScore,SymScore,VarScore\n');
        for i = 1:numel(images)
            d = images(i).detail;
            fprintf(fid,'%s,%s,%s,%d,%d,%d,%d,%d,%d,%d\n', ...
                images(i).poleNum, images(i).name, upper(images(i).status), ...
                images(i).conf, ...
                safeField(d,'crackScore'), safeField(d,'burnScore'), ...
                safeField(d,'contamScore'),safeField(d,'textureScore'), ...
                safeField(d,'symScore'),   safeField(d,'varScore'));
        end
        fclose(fid);
        msgbox(sprintf('Report saved to:\n%s',fullfile(fp,fn)),'Export Complete');
    end

    %% ── CLOSE ─────────────────────────────────────────────────
    function onClose(~,~)
        delete(fig);
    end

    %% ── HELPERS ───────────────────────────────────────────────
    function out = ternary(cond,a,b)
        if cond, out = a; else, out = b; end
    end

    function v = safeField(s,f)
        if isfield(s,f), v = s.(f); else, v = 0; end
    end

end
