import "phoenix_html"
import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"

let AutoDismiss = {
  mounted() {
    setTimeout(() => {
      this.el.style.transition = "opacity 300ms"
      this.el.style.opacity = "0"
      setTimeout(() => this.el.remove(), 300)
    }, 3000)
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

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
let liveSocket = new LiveSocket("/live", Socket, {
  params: { _csrf_token: csrfToken },
  hooks: { AutoDismiss, ImagePreview, CopyLink }
})

liveSocket.connect()
