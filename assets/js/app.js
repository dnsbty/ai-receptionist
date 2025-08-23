// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"
import { AsYouType } from "libphonenumber-js";
import { hooks as colocatedHooks } from "phoenix-colocated/receptionist"
import topbar from "topbar"

const Hooks = {};

Hooks.PhoneInput = {
  mounted() {
    this.el.addEventListener("input", () => {
      let asYouType = new AsYouType("US");
      const input = this.el.value;
      let output = input.replace(/\D/g, "");
      if (output.length > 4) {
        output = asYouType.input(input);
      }
      this.el.value = output;
    });
  },
};

Hooks.CurrentTimeIndicator = {
  mounted() {
    this.timezone = this.el.dataset.timezone || "America/Denver";
    this.scrollContainer = document.getElementById("calendar-scroll-container");

    // Scroll to 7am on mount
    this.scrollToHour(7);

    this.updateTimeIndicator();
    // Update every minute
    this.timer = setInterval(() => this.updateTimeIndicator(), 60000);
  },

  destroyed() {
    if (this.timer) {
      clearInterval(this.timer);
    }
  },

  scrollToHour(hour) {
    if (!this.scrollContainer) return;

    // Each hour is 48px (h-12 in Tailwind)
    const hourHeight = 48;
    const scrollPosition = hour * hourHeight;

    // Scroll to the position
    this.scrollContainer.scrollTop = scrollPosition;
  },

  scrollToCurrentTime() {
    if (!this.scrollContainer) return;

    const now = new Date();
    const hours = now.getHours();
    const minutes = now.getMinutes();

    // Calculate scroll position
    const hourHeight = 48;
    const scrollPosition = (hours + minutes / 60) * hourHeight;

    // Only scroll if current time is outside visible area
    const containerHeight = this.scrollContainer.clientHeight;
    const currentScroll = this.scrollContainer.scrollTop;

    if (scrollPosition < currentScroll || scrollPosition > currentScroll + containerHeight - hourHeight) {
      // Scroll to center the current time
      this.scrollContainer.scrollTop = scrollPosition - containerHeight / 2;
    }
  },

  updateTimeIndicator() {
    const now = new Date();
    const hours = now.getHours();
    const minutes = now.getMinutes();

    // Calculate position as percentage of the day
    const totalMinutes = hours * 60 + minutes;
    const dayMinutes = 24 * 60;
    const position = (totalMinutes / dayMinutes) * 100;

    // Find the current time indicator element
    const indicator = document.getElementById("current-time-indicator");
    if (!indicator) return;

    // Get today's index from the data attribute
    const todayIndex = indicator.dataset.todayIndex;

    // Only show if today is in the current week view
    if (todayIndex !== null && todayIndex !== undefined && todayIndex !== "") {
      indicator.classList.remove("hidden");
      indicator.style.top = `${position}%`;

      // Update the column line position
      const columnLine = document.getElementById("time-line-column");
      if (columnLine) {
        const columnWidth = 100 / 7; // 7 days in week
        columnLine.style.left = `calc(${todayIndex} * ${columnWidth}%)`;
        columnLine.style.width = `${columnWidth}%`;
      }

      // Optionally scroll to current time if it's today
      // Only do this on initial mount, not every minute
      if (!this.hasScrolledToCurrentTime) {
        const currentHour = now.getHours();
        // If current time is between 5am and 9pm, scroll to current time
        // Otherwise stick with 5am default
        if (currentHour >= 5 && currentHour <= 21) {
          this.scrollToCurrentTime();
        }
        this.hasScrolledToCurrentTime = true;
      }
    } else {
      indicator.classList.add("hidden");
    }

    // Update the hour labels to show current time
    const hourSpans = this.el.querySelectorAll("span[data-hour]");
    hourSpans.forEach(span => {
      const hour = parseInt(span.dataset.hour);
      if (hour === hours) {
        // Format current time
        const timeStr = this.formatTime(hours, minutes);
        span.innerHTML = `<span class="text-red-600 font-bold">${timeStr}</span>`;
      } else {
        // Reset to normal hour display
        span.innerHTML = this.formatHour(hour);
      }
    });
  },

  formatTime(hour, minute) {
    const minuteStr = minute.toString().padStart(2, '0');
    const period = hour >= 12 ? 'PM' : 'AM';
    const hour12 = hour === 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    return `${hour12}:${minuteStr} ${period}`;
  },

  formatHour(hour) {
    if (hour === 0) return "12 AM";
    if (hour < 12) return `${hour} AM`;
    if (hour === 12) return "12 PM";
    return `${hour - 12} PM`;
  }
};

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {
    _csrf_token: csrfToken,
    timezone: Intl.DateTimeFormat().resolvedOptions().timeZone
  },
  hooks: { ...Hooks, ...colocatedHooks },
})

// Show progress bar on live navigation and form submits
topbar.config({ barColors: { 0: "#29d" }, shadowColor: "rgba(0, 0, 0, .3)" })
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({ detail: reloader }) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", e => keyDown = null)
    window.addEventListener("click", e => {
      if (keyDown === "c") {
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if (keyDown === "d") {
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}

