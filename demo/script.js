(function () {
  var params = new URLSearchParams(window.location.search);
  var flash = params.get("flash") === "1" || params.get("state") === "flash";
  var caption =
    params.get("caption") === "1" || params.get("state") === "caption";
  var keys = params.get("keys") || "copy";
  var sceneParam = params.get("scene") || "";
  var play = params.get("play") === "1";

  var frame = document.querySelector(".frame");
  var captionEl = document.querySelector(".caption-overlay");
  var captionKeysEl = document.querySelector(".caption-keys");
  var flashEl = document.querySelector(".flash-overlay");
  var terminalPasted = document.querySelector(".terminal-pasted");
  var terminalThinking = document.querySelector(".terminal-thinking");
  var terminalTyped = document.querySelector(".terminal-typed");
  var terminalCursor = document.querySelector(".terminal-cursor");

  var sceneIndex = { jira: 0, slack: 1, github: 2, terminal: 3 }[sceneParam] ?? 0;
  if (!play) frame.setAttribute("data-scene-index", String(sceneIndex));

  if (!play) {
    if (caption && captionEl && captionKeysEl) {
      captionKeysEl.textContent =
        keys === "paste" ? "\u2303 \u2318 V" : "\u2303 \u2318 C";
      if (keys === "paste") captionEl.classList.add("caption-paste");
      captionEl.classList.add("caption-visible");
    }
    if (flash && flashEl) {
      flashEl.hidden = false;
      frame.classList.add("trigger-flash");
      flashEl.addEventListener(
        "animationend",
        function () {
          frame.classList.remove("trigger-flash");
        },
        { once: true }
      );
    }
  }

  if (play && frame && captionEl && captionKeysEl && flashEl) {
    flashEl.hidden = false;
    captionEl.classList.remove("caption-visible");
    if (terminalPasted) terminalPasted.hidden = true;
    if (terminalThinking) {
      terminalThinking.hidden = true;
      terminalThinking.textContent = "";
    }
    if (terminalTyped) terminalTyped.textContent = "";
    if (terminalCursor) terminalCursor.classList.remove("terminal-cursor-off");

    function setScene(index) {
      frame.setAttribute("data-scene-index", String(index));
    }

    function showCaption(copyOrPaste) {
      captionKeysEl.textContent =
        copyOrPaste === "paste" ? "\u2303 \u2318 V" : "\u2303 \u2318 C";
      captionEl.classList.remove("caption-paste");
      if (copyOrPaste === "paste") captionEl.classList.add("caption-paste");
      captionEl.classList.add("caption-visible");
    }

    function hideCaption() {
      captionEl.classList.remove("caption-visible", "caption-paste");
    }

    function runFlash() {
      frame.classList.add("trigger-flash");
      flashEl.addEventListener(
        "animationend",
        function () {
          frame.classList.remove("trigger-flash");
        },
        { once: true }
      );
    }

    function typePrompt(text, cb) {
      if (!terminalTyped) {
        if (cb) cb();
        return;
      }
      var i = 0;
      function addChar() {
        if (i < text.length) {
          terminalTyped.textContent += text[i];
          i += 1;
          setTimeout(addChar, 80);
        } else {
          if (terminalCursor) terminalCursor.classList.add("terminal-cursor-off");
          if (cb) setTimeout(cb, 200);
        }
      }
      addChar();
    }

    function runThinkingAnimation() {
      if (!terminalThinking) return;
      terminalThinking.hidden = false;
      terminalThinking.textContent = "Thinking";
      var step = 0;
      var interval = 500;
      var id = setInterval(function () {
        step += 1;
        var dots = Math.min(step, 5);
        terminalThinking.textContent = "Thinking" + ".".repeat(dots);
        if (step >= 5) clearInterval(id);
      }, interval);
    }

    var t = 0;
    function step(delay, fn) {
      t += delay;
      setTimeout(fn, t * 1000);
    }

    setScene(0);
    step(2, function () {
      showCaption("copy");
      setTimeout(function () {
        runFlash();
      }, 200);
    });
    step(1.5, function () {
      hideCaption();
    });
    step(0.5, function () {
      setScene(1);
    });
    step(1, function () {
      showCaption("copy");
      setTimeout(function () {
        runFlash();
      }, 200);
    });
    step(1.5, function () {
      hideCaption();
    });
    step(0.5, function () {
      setScene(2);
    });
    step(1, function () {
      showCaption("copy");
      setTimeout(function () {
        runFlash();
      }, 200);
    });
    step(1.5, function () {
      hideCaption();
    });
    step(0.5, function () {
      setScene(3);
    });
    step(0.5, function () {
      typePrompt("fix this", function () {
        setTimeout(function () {
          showCaption("paste");
          setTimeout(function () {
            runFlash();
          }, 200);
          setTimeout(function () {
            if (terminalPasted) terminalPasted.hidden = false;
            runThinkingAnimation();
          }, 800);
          setTimeout(function () {
            hideCaption();
          }, 2000);
        }, 300);
      });
    });
  }
})();
