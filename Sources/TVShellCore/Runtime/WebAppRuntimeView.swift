import SwiftUI
import WebKit

public struct WebAppRuntimeView: NSViewRepresentable {
    public let app: TVAppProfile
    public let webZoom: Double
    public let webRemoteMode: WebRemoteMode

    public init(app: TVAppProfile, webZoom: Double, webRemoteMode: WebRemoteMode = .mouse) {
        self.app = app
        self.webZoom = webZoom
        self.webRemoteMode = webRemoteMode
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(initialMode: webRemoteMode)
    }

    public func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let userScript = WKUserScript(
            source: Self.remoteBridgeScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
        configuration.userContentController.addUserScript(userScript)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsMagnification = true
        webView.pageZoom = webZoom
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        context.coordinator.attach(to: webView)
        context.coordinator.applyMode(webRemoteMode)

        if case let .web(url) = app.target {
            webView.load(URLRequest(url: url))
        }

        return webView
    }

    public func updateNSView(_ webView: WKWebView, context: Context) {
        webView.pageZoom = webZoom
        context.coordinator.applyMode(webRemoteMode)
    }

    @MainActor
    public final class Coordinator: NSObject, WKNavigationDelegate {
        private weak var webView: WKWebView?
        private nonisolated(unsafe) var observer: NSObjectProtocol?
        private var currentMode: WebRemoteMode

        init(initialMode: WebRemoteMode) {
            currentMode = initialMode
        }

        deinit {
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
        }

        public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            applyMode(currentMode)
        }

        func attach(to webView: WKWebView) {
            self.webView = webView
            if observer == nil {
                observer = NotificationCenter.default.addObserver(
                    forName: .tvShellRuntimeCommand,
                    object: nil,
                    queue: .main
                ) { [weak self] notification in
                    guard let command = notification.userInfo?[RuntimeCommandNotification.commandKey] as? RemoteCommand else {
                        return
                    }
                    let mode = notification.userInfo?[RuntimeCommandNotification.webModeKey] as? WebRemoteMode ?? .keyboard
                    Task { @MainActor [weak self] in
                        self?.send(command, mode: mode)
                    }
                }
            }
        }

        private func send(_ command: RemoteCommand, mode: WebRemoteMode) {
            guard let webView else {
                return
            }
            currentMode = mode
            if command == .menu {
                applyMode(mode)
                return
            }

            let jsCommand = command.javascriptName
            guard jsCommand.isEmpty == false else {
                return
            }

            webView.evaluateJavaScript("window.tvShellCommand && window.tvShellCommand('\(jsCommand)', '\(mode.rawValue)')") { _, _ in }
        }

        func applyMode(_ mode: WebRemoteMode) {
            currentMode = mode
            guard let webView else {
                return
            }
            webView.evaluateJavaScript("window.tvShellSetMode && window.tvShellSetMode('\(mode.rawValue)')") { _, _ in }
        }
    }

    public static let remoteBridgeScript = """
    (() => {
      if (window.__tvShellInstalled) return;
      window.__tvShellInstalled = true;

      const style = document.createElement('style');
      style.textContent = `
        :focus {
          outline: 6px solid rgba(255,255,255,.96) !important;
          outline-offset: 8px !important;
        }
        button, a, input, select, textarea, [role="button"], [tabindex] {
          min-height: 44px !important;
          min-width: 44px !important;
        }
        #tv-shell-cursor {
          position: fixed !important;
          z-index: 2147483647 !important;
          width: 34px !important;
          height: 34px !important;
          border-radius: 999px !important;
          border: 4px solid rgba(255,255,255,.96) !important;
          background: radial-gradient(circle at 35% 35%, rgba(255,255,255,.88), rgba(80,200,255,.30) 45%, rgba(255,255,255,.08)) !important;
          box-shadow: 0 0 28px rgba(80,200,255,.72), 0 12px 26px rgba(0,0,0,.38) !important;
          transform: translate(-50%, -50%) !important;
          pointer-events: none !important;
          transition: left .12s ease-out, top .12s ease-out, transform .08s ease-out !important;
        }
        #tv-shell-cursor.tv-shell-click {
          transform: translate(-50%, -50%) scale(.72) !important;
        }
        #tv-shell-cursor-label {
          position: fixed !important;
          z-index: 2147483647 !important;
          left: 50% !important;
          bottom: 36px !important;
          transform: translateX(-50%) !important;
          padding: 14px 22px !important;
          border-radius: 999px !important;
          color: white !important;
          font: 700 22px -apple-system, BlinkMacSystemFont, "SF Pro Display", sans-serif !important;
          letter-spacing: 0 !important;
          background: rgba(20, 24, 34, .74) !important;
          border: 1px solid rgba(255,255,255,.32) !important;
          box-shadow: 0 12px 34px rgba(0,0,0,.35) !important;
          backdrop-filter: blur(18px) saturate(150%) !important;
          pointer-events: none !important;
          transition: opacity .18s ease-out !important;
        }
        .tv-shell-cursor-hidden {
          opacity: 0 !important;
        }
        #tv-shell-keyboard {
          position: fixed !important;
          z-index: 2147483647 !important;
          left: 50% !important;
          bottom: 28px !important;
          transform: translateX(-50%) !important;
          width: min(980px, calc(100vw - 72px)) !important;
          padding: 22px !important;
          border-radius: 28px !important;
          color: white !important;
          background: rgba(18, 22, 32, .82) !important;
          border: 1px solid rgba(255,255,255,.28) !important;
          box-shadow: 0 20px 54px rgba(0,0,0,.46) !important;
          backdrop-filter: blur(22px) saturate(160%) !important;
          pointer-events: none !important;
          font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", sans-serif !important;
        }
        #tv-shell-keyboard.tv-shell-hidden {
          display: none !important;
        }
        .tv-shell-keyboard-preview {
          font-size: 28px !important;
          font-weight: 800 !important;
          min-height: 38px !important;
          margin-bottom: 14px !important;
          white-space: nowrap !important;
          overflow: hidden !important;
          text-overflow: ellipsis !important;
        }
        .tv-shell-keyboard-row {
          display: flex !important;
          justify-content: center !important;
          gap: 10px !important;
          margin-top: 10px !important;
        }
        .tv-shell-key {
          min-width: 54px !important;
          height: 50px !important;
          padding: 0 14px !important;
          border-radius: 16px !important;
          display: grid !important;
          place-items: center !important;
          font-size: 22px !important;
          font-weight: 800 !important;
          background: rgba(255,255,255,.12) !important;
          border: 1px solid rgba(255,255,255,.20) !important;
        }
        .tv-shell-key.tv-shell-focused {
          background: rgba(120,210,255,.38) !important;
          border-color: rgba(255,255,255,.82) !important;
          box-shadow: 0 0 22px rgba(90,200,255,.52) !important;
          transform: scale(1.08) !important;
        }
      `;
      document.documentElement.appendChild(style);

      const cursorState = {
        x: Math.round(window.innerWidth / 2),
        y: Math.round(window.innerHeight / 2),
        visible: false
      };
      const keyboardLayouts = {
        zhuyin: [
          ['ㄅ','ㄉ','ˇ','ˋ','ㄓ','ˊ','˙','ㄚ','ㄞ','ㄢ','ㄦ'],
          ['ㄆ','ㄊ','ㄍ','ㄐ','ㄔ','ㄗ','ㄧ','ㄛ','ㄟ','ㄣ'],
          ['ㄇ','ㄋ','ㄎ','ㄑ','ㄕ','ㄘ','ㄨ','ㄜ','ㄠ','ㄤ'],
          ['ㄈ','ㄌ','ㄏ','ㄒ','ㄖ','ㄙ','ㄩ','ㄝ','ㄡ','ㄥ'],
          ['空格','刪除','完成','ABC']
        ],
        latin: [
          ['1','2','3','4','5','6','7','8','9','0'],
          ['Q','W','E','R','T','Y','U','I','O','P'],
          ['A','S','D','F','G','H','J','K','L'],
          ['Z','X','C','V','B','N','M'],
          ['SPACE','DELETE','DONE','注音']
        ]
      };
      const zhuyinMap = {
        'ㄅ': ['不'],
        'ㄧ': ['一'],
        'ㄨㄛˇ': ['我'],
        'ㄋㄧˇ': ['你'],
        'ㄊㄚ': ['他','她','它'],
        'ㄕˋ': ['是','事','市','式'],
        'ㄧㄡˇ': ['有'],
        'ㄗㄞˋ': ['在','再'],
        'ㄅㄨˋ': ['不'],
        'ㄓㄜˋ': ['這'],
        'ㄋㄚˋ': ['那'],
        'ㄌㄜ˙': ['了'],
        'ㄧˇ': ['以','已'],
        'ㄉㄚˋ': ['大'],
        'ㄒㄧㄠˇ': ['小'],
        'ㄍㄜˋ': ['個'],
        'ㄏㄨㄟˋ': ['會'],
        'ㄨㄟˋ': ['為','位'],
        'ㄌㄞˊ': ['來'],
        'ㄐㄧㄡˋ': ['就'],
        'ㄉㄠˋ': ['到','道'],
        'ㄧㄠˋ': ['要'],
        'ㄧㄡˋ': ['又'],
        'ㄑㄩˋ': ['去'],
        'ㄏㄠˇ': ['好'],
        'ㄇㄟˊ': ['沒'],
        'ㄏㄣˇ': ['很'],
        'ㄉㄨㄛ': ['多'],
        'ㄕㄠˇ': ['少'],
        'ㄎㄢˋ': ['看'],
        'ㄊㄧㄥ': ['聽'],
        'ㄕㄨㄛ': ['說'],
        'ㄒㄧㄤˇ': ['想'],
        'ㄔ': ['吃'],
        'ㄏㄜ': ['喝'],
        'ㄇㄞˇ': ['買'],
        'ㄇㄞˋ': ['賣'],
        'ㄕㄨㄟˇ': ['水'],
        'ㄏㄨㄛˇ': ['火'],
        'ㄕㄢ': ['山'],
        'ㄖˋ': ['日'],
        'ㄩㄝˋ': ['月'],
        'ㄋㄧㄢˊ': ['年'],
        'ㄊㄧㄢ': ['天'],
        'ㄇㄧㄥˊ': ['名','明'],
        'ㄗˋ': ['字'],
        'ㄑㄧㄥˇ': ['請'],
        'ㄒㄧㄝˋ': ['謝'],
        'ㄌㄠˇ': ['老'],
        'ㄕ': ['師'],
        'ㄌㄠˇㄕ': ['老師'],
        'ㄒㄩㄝˊㄕㄥ': ['學生'],
        'ㄨㄤˇ': ['網'],
        'ㄌㄨˋ': ['路'],
        'ㄨㄤˇㄌㄨˋ': ['網路'],
        'ㄩㄢˊ': ['源','員','原'],
        'ㄓㄨˇ': ['主'],
        'ㄧㄝˇ': ['也'],
        'ㄎㄜˇ': ['可'],
        'ㄎㄚˇ': ['卡'],
        'ㄎㄧㄚˇ': ['卡'],
        'ㄎㄜˇㄎㄜˇ': ['可可'],
        'ㄉㄧㄢˋ': ['電','店'],
        'ㄉㄧㄢˇ': ['點'],
        'ㄋㄠˇ': ['腦'],
        'ㄧㄥˇ': ['影'],
        'ㄉㄧㄢˋㄋㄠˇ': ['電腦'],
        'ㄉㄧㄢˋㄧㄥˇ': ['電影'],
        'ㄈㄨˊ': ['芙'],
        'ㄌㄧˋ': ['莉'],
        'ㄌㄧㄢˊ': ['蓮'],
        'ㄓㄨˋ': ['注'],
        'ㄧㄣ': ['音'],
        'ㄓㄨˋㄧㄣ': ['注音'],
        'ㄉㄨㄥˋ': ['動'],
        'ㄇㄢˋ': ['漫'],
        'ㄉㄨㄥˋㄇㄢˋ': ['動漫'],
        'ㄓㄨㄥ': ['中'],
        'ㄨㄣˊ': ['文'],
        'ㄓㄨㄥㄨㄣˊ': ['中文'],
        'ㄍㄨㄟˇ': ['鬼'],
        'ㄇㄧㄝˋ': ['滅'],
        'ㄖㄣˋ': ['刃']
      };
      const keyboardRows = () => keyboardLayouts[keyboardState.layout];
      const zhuyinCandidates = () => {
        if (!keyboardState.composition) return [];
        if (zhuyinMap[keyboardState.composition]) return zhuyinMap[keyboardState.composition];
        const matches = Object.keys(zhuyinMap)
          .filter((key) => key.startsWith(keyboardState.composition) || keyboardState.composition.startsWith(key))
          .flatMap((key) => zhuyinMap[key]);
        return matches.length ? matches.slice(0, 6) : [keyboardState.composition];
      };
      const keyboardState = {
        visible: false,
        row: 0,
        column: 0,
        target: null,
        layout: 'zhuyin',
        composition: '',
        lastKey: null,
        candidateIndex: null
      };

      const ensureCursor = () => {
        let cursor = document.getElementById('tv-shell-cursor');
        if (!cursor) {
          cursor = document.createElement('div');
          cursor.id = 'tv-shell-cursor';
          document.documentElement.appendChild(cursor);
        }
        cursorState.visible = true;
        cursor.style.left = `${cursorState.x}px`;
        cursor.style.top = `${cursorState.y}px`;
        return cursor;
      };

      const ensureCursorLabel = (text = '虛擬滑鼠') => {
        let label = document.getElementById('tv-shell-cursor-label');
        if (!label) {
          label = document.createElement('div');
          label.id = 'tv-shell-cursor-label';
          document.documentElement.appendChild(label);
        }
        label.textContent = text;
        label.classList.remove('tv-shell-cursor-hidden');
        clearTimeout(label.__tvShellHideTimer);
        label.__tvShellHideTimer = setTimeout(() => {
          label.classList.add('tv-shell-cursor-hidden');
        }, 1800);
        return label;
      };

      const hideCursor = () => {
        const cursor = document.getElementById('tv-shell-cursor');
        if (cursor) cursor.classList.add('tv-shell-cursor-hidden');
      };

      window.tvShellSetMode = (mode = 'keyboard') => {
        if (mode === 'mouse') {
          const cursor = ensureCursor();
          cursor.classList.remove('tv-shell-cursor-hidden');
          ensureCursorLabel('虛擬滑鼠：方向鍵移動，OK 點擊');
          return true;
        }
        hideCursor();
        return true;
      };

      const activeInput = () => {
        const active = document.activeElement;
        if (!active) return null;
        const tag = active.tagName ? active.tagName.toLowerCase() : '';
        if (tag === 'input' || tag === 'textarea' || active.isContentEditable) return active;
        return keyboardState.target;
      };

      const inputValue = (target) => {
        if (!target) return '';
        if (target.isContentEditable) return target.textContent || '';
        return target.value || '';
      };

      const setInputValue = (target, value) => {
        if (!target) return;
        if (target.isContentEditable) {
          target.textContent = value;
        } else {
          target.value = value;
        }
        target.dispatchEvent(new Event('input', { bubbles: true }));
        target.dispatchEvent(new Event('change', { bubbles: true }));
      };

      const ensureKeyboard = () => {
        let keyboard = document.getElementById('tv-shell-keyboard');
        if (!keyboard) {
          keyboard = document.createElement('div');
          keyboard.id = 'tv-shell-keyboard';
          document.documentElement.appendChild(keyboard);
        }
        return keyboard;
      };

      const renderKeyboard = () => {
        const keyboard = ensureKeyboard();
        const target = activeInput();
        const preview = inputValue(target);
        const rows = keyboardRows();
        const candidates = zhuyinCandidates();
        keyboard.classList.toggle('tv-shell-hidden', !keyboardState.visible);
        keyboard.innerHTML = `
          <div class="tv-shell-keyboard-preview">${preview || keyboardState.composition || '輸入文字'}</div>
          ${keyboardState.composition ? `<div class="tv-shell-keyboard-row"><div class="tv-shell-key">${keyboardState.composition}</div>${candidates.map((item, index) => `<div class="tv-shell-key ${keyboardState.candidateIndex === index ? 'tv-shell-focused' : ''}">${item}</div>`).join('')}</div>` : ''}
          ${rows.map((row, rowIndex) => `
            <div class="tv-shell-keyboard-row">
              ${row.map((key, columnIndex) => `
                <div class="tv-shell-key ${keyboardState.candidateIndex === null && rowIndex === keyboardState.row && columnIndex === keyboardState.column ? 'tv-shell-focused' : ''}">${key}</div>
              `).join('')}
            </div>
          `).join('')}
        `;
      };

      const showKeyboard = (target = activeInput()) => {
        if (!target) return false;
        keyboardState.target = target;
        keyboardState.visible = true;
        renderKeyboard();
        return true;
      };

      const hideKeyboard = () => {
        keyboardState.visible = false;
        renderKeyboard();
      };

      const typeKeyboardKey = () => {
        const target = activeInput();
        if (!target) return false;
        const rows = keyboardRows();
        const key = rows[keyboardState.row][keyboardState.column];
        let value = inputValue(target);
        if (keyboardState.candidateIndex !== null) {
          const candidate = zhuyinCandidates()[keyboardState.candidateIndex];
          if (candidate) {
            value += candidate;
            setInputValue(target, value);
            keyboardState.composition = '';
            keyboardState.lastKey = null;
            keyboardState.candidateIndex = null;
          }
          renderKeyboard();
          return true;
        }
        if (key === 'ABC' || key === '注音') {
          keyboardState.layout = keyboardState.layout === 'zhuyin' ? 'latin' : 'zhuyin';
          keyboardState.row = 0;
          keyboardState.column = 0;
          keyboardState.composition = '';
          keyboardState.lastKey = null;
          keyboardState.candidateIndex = null;
          renderKeyboard();
          return true;
        }
        if (key === 'DONE' || key === '完成') {
          if (keyboardState.composition) {
            value += zhuyinCandidates()[0] || keyboardState.composition;
            setInputValue(target, value);
            keyboardState.composition = '';
            keyboardState.lastKey = null;
            keyboardState.candidateIndex = null;
          }
          hideKeyboard();
          target.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', code: 'Enter', bubbles: true }));
          return true;
        }
        if (key === 'DELETE' || key === '刪除') {
          if (keyboardState.composition) {
            keyboardState.composition = keyboardState.composition.slice(0, -1);
            keyboardState.lastKey = null;
            keyboardState.candidateIndex = null;
          } else {
            value = value.slice(0, -1);
          }
        } else if (key === 'SPACE' || key === '空格') {
          if (keyboardState.composition) {
            value += zhuyinCandidates()[0] || keyboardState.composition;
            keyboardState.composition = '';
            keyboardState.lastKey = null;
            keyboardState.candidateIndex = null;
          } else {
            value += ' ';
          }
        } else if (keyboardState.layout === 'zhuyin') {
          if (keyboardState.composition && key === keyboardState.lastKey) {
            value += zhuyinCandidates()[0] || keyboardState.composition;
            keyboardState.composition = '';
            keyboardState.lastKey = null;
            keyboardState.candidateIndex = null;
          } else {
            keyboardState.composition += key;
            keyboardState.lastKey = key;
            keyboardState.candidateIndex = null;
          }
        } else {
          value += key;
        }
        setInputValue(target, value);
        renderKeyboard();
        return true;
      };

      const keyboardKeyWidth = (key) => {
        if (key === '空格' || key === 'SPACE') return 150;
        if (['刪除','完成','ABC','DELETE','DONE','注音'].includes(key)) return 132;
        return 68;
      };
      const keyboardKeyCenter = (row, index) => {
        const leading = row.slice(0, index).reduce((sum, key) => sum + keyboardKeyWidth(key), 0);
        return leading + (index * 12) + (keyboardKeyWidth(row[index]) / 2);
      };
      const moveKeyboardFocus = (destinationRow) => {
        if (destinationRow === keyboardState.row) return;
        const rows = keyboardRows();
        const sourceCenter = keyboardKeyCenter(rows[keyboardState.row], keyboardState.column);
        const destination = rows[destinationRow];
        let nearest = 0;
        destination.forEach((_, index) => {
          if (Math.abs(keyboardKeyCenter(destination, index) - sourceCenter) < Math.abs(keyboardKeyCenter(destination, nearest) - sourceCenter)) {
            nearest = index;
          }
        });
        keyboardState.row = destinationRow;
        keyboardState.column = nearest;
      };

      const handleKeyboardCommand = (command) => {
        if (!keyboardState.visible) return false;
        const candidates = zhuyinCandidates();
        if (command === 'left') {
          if (keyboardState.candidateIndex !== null) keyboardState.candidateIndex = Math.max(0, keyboardState.candidateIndex - 1);
          else keyboardState.column = Math.max(0, keyboardState.column - 1);
        }
        if (command === 'right') {
          if (keyboardState.candidateIndex !== null) keyboardState.candidateIndex = Math.min(candidates.length - 1, keyboardState.candidateIndex + 1);
          else keyboardState.column = Math.min(keyboardRows()[keyboardState.row].length - 1, keyboardState.column + 1);
        }
        if (command === 'up') {
          if (keyboardState.candidateIndex !== null) {
            keyboardState.candidateIndex = Math.max(0, keyboardState.candidateIndex - 1);
          } else if (keyboardState.row === 0 && keyboardState.composition && candidates.length) {
            keyboardState.candidateIndex = Math.min(keyboardState.column, candidates.length - 1);
          } else {
            moveKeyboardFocus(Math.max(0, keyboardState.row - 1));
          }
        }
        if (command === 'down') {
          if (keyboardState.candidateIndex !== null) {
            keyboardState.column = Math.min(keyboardState.candidateIndex, keyboardRows()[keyboardState.row].length - 1);
            keyboardState.candidateIndex = null;
          } else {
            moveKeyboardFocus(Math.min(keyboardRows().length - 1, keyboardState.row + 1));
          }
        }
        if (command === 'select') return typeKeyboardKey();
        if (command === 'back') {
          const target = activeInput();
          if (target && inputValue(target).length > 0) {
            setInputValue(target, inputValue(target).slice(0, -1));
            keyboardState.candidateIndex = null;
          } else {
            hideKeyboard();
          }
        }
        renderKeyboard();
        return ['up', 'down', 'left', 'right', 'select', 'back'].includes(command);
      };

      document.addEventListener('focusin', (event) => {
        const target = event.target;
        const tag = target && target.tagName ? target.tagName.toLowerCase() : '';
        if (tag === 'input' || tag === 'textarea' || target.isContentEditable) {
          showKeyboard(target);
        }
      }, true);

      const moveCursor = (dx, dy) => {
        cursorState.x = Math.max(18, Math.min(window.innerWidth - 18, cursorState.x + dx));
        cursorState.y = Math.max(18, Math.min(window.innerHeight - 18, cursorState.y + dy));
        ensureCursor();
        const target = document.elementFromPoint(cursorState.x, cursorState.y);
        if (target && target.focus) {
          try { target.focus({ preventScroll: true }); } catch (_) {}
        }
        return true;
      };

      const clickCursor = () => {
        const cursor = ensureCursor();
        const target = document.elementFromPoint(cursorState.x, cursorState.y);
        cursor.classList.add('tv-shell-click');
        setTimeout(() => cursor.classList.remove('tv-shell-click'), 110);
        if (!target) return false;
        const init = {
          bubbles: true,
          cancelable: true,
          view: window,
          clientX: cursorState.x,
          clientY: cursorState.y,
          button: 0,
          buttons: 1
        };
        target.dispatchEvent(new MouseEvent('mousemove', init));
        target.dispatchEvent(new MouseEvent('mousedown', init));
        target.dispatchEvent(new MouseEvent('mouseup', { ...init, buttons: 0 }));
        target.dispatchEvent(new MouseEvent('click', { ...init, buttons: 0 }));
        if (target.click) target.click();
        return true;
      };

      window.tvShellCommand = (command, mode = 'keyboard') => {
        if (handleKeyboardCommand(command)) return true;

        const keyForCommand = {
          up: 'ArrowUp',
          down: 'ArrowDown',
          left: 'ArrowLeft',
          right: 'ArrowRight',
          select: 'Enter',
          back: 'Escape',
          playPause: ' '
        }[command];

        const dispatchKey = () => {
          if (!keyForCommand) return false;
          const eventInit = {
            key: keyForCommand,
            code: keyForCommand === ' ' ? 'Space' : keyForCommand,
            bubbles: true,
            cancelable: true,
            composed: true
          };
          document.dispatchEvent(new KeyboardEvent('keydown', eventInit));
          if (document.activeElement) {
            document.activeElement.dispatchEvent(new KeyboardEvent('keydown', eventInit));
          }
          document.dispatchEvent(new KeyboardEvent('keyup', eventInit));
          return true;
        };

        const active = document.activeElement;
        const focusables = Array.from(document.querySelectorAll('a, button, input, select, textarea, video, [role="button"], [tabindex]:not([tabindex="-1"])'))
          .filter(el => !el.disabled && el.offsetParent !== null);

        const currentIndex = Math.max(0, focusables.indexOf(active));
        const focusAt = (index) => {
          const next = focusables[Math.max(0, Math.min(index, focusables.length - 1))];
          if (next && next.focus) {
            next.focus({ preventScroll: false });
            next.scrollIntoView({ block: 'center', inline: 'center', behavior: 'smooth' });
          } else if (command === 'down') {
            window.scrollBy({ top: window.innerHeight * 0.65, behavior: 'smooth' });
          } else if (command === 'up') {
            window.scrollBy({ top: -window.innerHeight * 0.65, behavior: 'smooth' });
          }
        };

        const scrollByCommand = () => {
          if (command === 'down') window.scrollBy({ top: window.innerHeight * 0.65, behavior: 'smooth' });
          if (command === 'up') window.scrollBy({ top: -window.innerHeight * 0.65, behavior: 'smooth' });
          if (command === 'right') window.scrollBy({ left: window.innerWidth * 0.65, behavior: 'smooth' });
          if (command === 'left') window.scrollBy({ left: -window.innerWidth * 0.65, behavior: 'smooth' });
          return ['up', 'down', 'left', 'right'].includes(command);
        };
        const remoteScrollByCommand = () => {
          if (command === 'fastForward') {
            window.scrollBy({ top: window.innerHeight * 0.72, behavior: 'smooth' });
            return true;
          }
          if (command === 'rewind') {
            window.scrollBy({ top: -window.innerHeight * 0.72, behavior: 'smooth' });
            return true;
          }
          return false;
        };

        if (remoteScrollByCommand()) return true;

        if (mode === 'keyboard') {
          const sent = dispatchKey();
          if (command === 'select' && active && active.click) active.click();
          if (command === 'playPause') {
            const video = document.querySelector('video');
            if (video) {
              if (video.paused) video.play(); else video.pause();
            }
          }
          return sent;
        }

        if (mode === 'scroll') {
          if (command === 'select' && active && active.click) return active.click(), true;
          if (command === 'playPause') dispatchKey();
          return scrollByCommand();
        }

        if (mode === 'mouse') {
          ensureCursor();
          ensureCursorLabel('虛擬滑鼠：方向鍵移動，OK 點擊');
          const step = Math.max(34, Math.round(Math.min(window.innerWidth, window.innerHeight) * 0.075));
          if (command === 'up') return moveCursor(0, -step);
          if (command === 'down') return moveCursor(0, step);
          if (command === 'left') return moveCursor(-step, 0);
          if (command === 'right') return moveCursor(step, 0);
          if (command === 'select') {
            const target = document.elementFromPoint(cursorState.x, cursorState.y);
            const tag = target && target.tagName ? target.tagName.toLowerCase() : '';
            if (target && (tag === 'input' || tag === 'textarea' || target.isContentEditable)) {
              try { target.focus({ preventScroll: true }); } catch (_) {}
              return showKeyboard(target);
            }
            return clickCursor();
          }
          if (command === 'playPause') return dispatchKey();
          return false;
        }

        if (command === 'select') {
          if (active && active.click) active.click();
          dispatchKey();
          return true;
        }
        if (command === 'back') {
          dispatchKey();
          history.back();
          return true;
        }
        if (command === 'down' || command === 'right') {
          dispatchKey();
          focusAt(currentIndex + 1);
          return true;
        }
        if (command === 'up' || command === 'left') {
          dispatchKey();
          focusAt(currentIndex - 1);
          return true;
        }
        if (command === 'playPause') {
          const video = document.querySelector('video');
          if (video) {
            if (video.paused) video.play(); else video.pause();
            return true;
          }
          dispatchKey();
        }
        return false;
      };
    })();
    """
}

private extension RemoteCommand {
    var javascriptName: String {
        switch self {
        case .up: "up"
        case .down: "down"
        case .left: "left"
        case .right: "right"
        case .select: "select"
        case .back: "back"
        case .playPause: "playPause"
        case .rewind: "rewind"
        case .fastForward: "fastForward"
        default: ""
        }
    }
}
