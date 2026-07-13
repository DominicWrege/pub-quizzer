import "phoenix_html"
import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"

let AutoDismiss = {
  mounted() {
    let duration = parseInt(this.el.dataset.duration) || 3000
    setTimeout(() => {
      this.el.style.transition = "opacity 300ms"
      this.el.style.opacity = "0"
      setTimeout(() => this.el.remove(), 300)
    }, duration)
  }
}

let ImagePreview = {
  mounted() {
    this.el.addEventListener("change", (e) => {
      if (e.target.type !== "file") return
      const file = e.target.files[0]
      if (!file) return
      const reader = new FileReader()
      reader.onload = (ev) => {
        this.pushEvent("image_preview", { data_url: ev.target.result })
      }
      reader.readAsDataURL(file)
    })
  }
}

let CopyLink = {
  mounted() {
    const url = this.el.dataset.url
    this.orig = this.el.innerHTML
    this.el.addEventListener("click", () => {
      navigator.clipboard.writeText(url).then(() => {
        this.el.innerHTML = "Kopiert!"
        this.el.classList.add("btn-success")
        setTimeout(() => {
          this.el.innerHTML = this.orig
          this.el.classList.remove("btn-success")
        }, 1500)
      })
    })
  }
}

let ClipboardCopy = {
  mounted() {
    this.handleEvent("copy_to_clipboard", ({ url }) => {
      navigator.clipboard.writeText(url)
    })
  }
}

let ScrollToBottom = {
  mounted() {
    if (localStorage.getItem("pm") === "true") {
      document.body.classList.add("presentation-mode")
    }
    this.handleEvent("scroll_to_bottom", () => {
      requestAnimationFrame(() => {
        this.el.scrollIntoView({ behavior: "smooth", block: "end" })
      })
    })
    this._keydown = (e) => {
      if (e.key === "p" || e.key === "P") {
        const active = document.body.classList.toggle("presentation-mode")
        localStorage.setItem("pm", active)
      }
    }
    document.addEventListener("keydown", this._keydown)
  },
  destroyed() {
    document.removeEventListener("keydown", this._keydown)
  }
}

let Dialog = {
  mounted() {
    this._closing = false
    this.el.addEventListener("close", () => {
      if (this._closing) {
        this._closing = false
        return
      }
      this.pushEvent(this.el.dataset.cancelEvent || "cancel_confirm")
    })
  },
  updated() {
    if (this.el.hasAttribute("data-show")) {
      if (!this.el.open) {
        this.el.showModal()
      }
    } else {
      if (this.el.open) {
        this._closing = true
        this.el.close()
      }
    }
  }
}

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
let liveSocket = new LiveSocket("/live", Socket, {
  params: { _csrf_token: csrfToken },
  hooks: { AutoDismiss, ImagePreview, CopyLink, ClipboardCopy, ScrollToBottom, Dialog }
})

liveSocket.connect()
