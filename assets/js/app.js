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
      this.previewFile(e.target.files[0])
    })
    this.el.addEventListener("drop", (e) => {
      const file = e.dataTransfer?.files?.[0]
      if (file) this.previewFile(file)
    })
  },
  previewFile(file) {
    if (!file) return
    const reader = new FileReader()
    reader.onload = (ev) => {
      this.pushEvent("image_preview", { data_url: ev.target.result })
    }
    reader.readAsDataURL(file)
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
    var qfz = parseInt(localStorage.getItem("qfz")) || 0
    document.body.dataset.quizFontSize = qfz
    var label = document.getElementById("qfz-label")
    if (label) label.textContent = ["80%","90%","100%","125%","150%","200%"][qfz + 2]
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

let OptionSorter = {
  mounted() {
    this._fromIdx = null
    this._clone = null
    this._rowHeight = 0
    this._onMove = null
    this._onUp = null
    this._lastTarget = null

    this.el.addEventListener('mousedown', (e) => {
      const handle = e.target.closest('.drag-handle')
      if (!handle) return
      e.preventDefault()
      this._startDrag(e.clientX, e.clientY, handle)
    })
  },

  destroyed() {
    this._cleanup()
  },

  _startDrag(cx, cy, handle) {
    const row = handle.closest('.opt-row')
    if (!row) return
    this._fromIdx = parseInt(row.dataset.index)
    this._rowHeight = row.offsetHeight + 8

    // Floating clone that follows the cursor
    this._clone = row.cloneNode(true)
    this._clone.style.position = 'fixed'
    this._clone.style.pointerEvents = 'none'
    this._clone.style.zIndex = '50'
    this._clone.style.width = row.offsetWidth + 'px'
    this._clone.style.opacity = '0.92'
    this._clone.style.boxShadow = '0 8px 28px oklch(0 0 0 / 0.18)'
    this._clone.style.borderRadius = '0.5rem'
    this._clone.style.transition = 'none'
    document.body.appendChild(this._clone)
    this._positionClone(cx, cy)

    // Placeholder: dim the original row
    row.classList.add('opacity-15')

    // Scoped event listeners (cleanup on mouseup)
    this._onMove = (ev) => {
      ev.preventDefault()
      this._positionClone(ev.clientX, ev.clientY)
      this._shiftAt(ev.clientY)
    }
    this._onUp = (ev) => {
      this._endDrag(ev.clientY)
    }

    document.addEventListener('mousemove', this._onMove)
    document.addEventListener('mouseup', this._onUp)
  },

  _positionClone(cx, cy) {
    if (!this._clone) return
    this._clone.style.left = (cx + 14) + 'px'
    this._clone.style.top = (cy + 10) + 'px'
  },

  _shiftAt(cy) {
    const rows = this.el.querySelectorAll('.opt-row')
    const target = this._resolveTarget(rows, cy)
    if (target === this._lastTarget) return
    this._lastTarget = target

    // Reset all transforms and highlights
    rows.forEach((r, i) => {
      r.style.transform = ''
      r.classList.remove('border-primary', 'bg-base-200')
    })

    if (target === this._fromIdx || target === this._fromIdx + 1) {
      if (rows[this._fromIdx]) rows[this._fromIdx].classList.add('border-primary', 'bg-base-200')
      return
    }

    // Shift intervening rows to open a gap
    if (target > this._fromIdx) {
      for (let i = this._fromIdx + 1; i < target && i < rows.length; i++) {
        rows[i].style.transform = `translateY(-${this._rowHeight}px)`
      }
    } else {
      for (let i = target; i < this._fromIdx; i++) {
        rows[i].style.transform = `translateY(${this._rowHeight}px)`
      }
    }

    // Highlight insertion point
    const insertIdx = target > this._fromIdx ? target - 1 : target
    if (rows[insertIdx] && insertIdx !== this._fromIdx) {
      rows[insertIdx].classList.add('border-primary', 'bg-base-200')
    }
  },

  _resolveTarget(rows, cy) {
    // Find the row whose vertical midpoint is closest to the cursor
    let closestIdx = 0
    let minDist = Infinity
    rows.forEach((r, i) => {
      const rect = r.getBoundingClientRect()
      const dist = Math.abs(cy - (rect.top + rect.height / 2))
      if (dist < minDist) { minDist = dist; closestIdx = i }
    })

    const rect = rows[closestIdx].getBoundingClientRect()
    return cy < rect.top + rect.height / 2 ? closestIdx : closestIdx + 1
  },

  _endDrag(cy) {
    this._cleanupClone()

    const rows = this.el.querySelectorAll('.opt-row')
    const target = this._resolveTarget(rows, cy)

    if (this._fromIdx === null || target === this._fromIdx) {
      this._resetRows()
      return
    }

    const from = this._fromIdx
    const to = target > from ? target - 1 : target

    if (from === to) { this._resetRows(); return }

    this._reorder(from, to)
  },

  _reorder(from, to) {
    const rows = this.el.querySelectorAll('.opt-row')
    const moving = rows[from]

    // Save checked state — some browsers reset radio groups on DOM detach
    const checkedRadio = this.el.querySelector('input[type="radio"]:checked')
    const savedCheckedVal = checkedRadio ? checkedRadio.value : null

    // Remove transforms so items settle via CSS transition
    Array.from(rows).forEach(r => { r.style.transform = '' })

    moving.remove()
    const ref = to >= this.el.children.length ? null : this.el.children[to]
    this.el.insertBefore(moving, ref)

    this._updateIndices()

    // Restore checked state if browser reset it
    if (savedCheckedVal !== null) {
      const restored = this.el.querySelector(`input[type="radio"][value="${savedCheckedVal}"]`)
      if (restored && !restored.checked) restored.checked = true
    }

    this._resetRows()

    // Trigger validation
    const ta = moving.querySelector('textarea')
    ta.dispatchEvent(new Event('input', { bubbles: true }))
  },

  _updateIndices() {
    this.el.querySelectorAll('.opt-row').forEach((row, i) => {
      row.dataset.index = i
      const radio = row.querySelector('input[type="radio"]')
      radio.value = i
      radio.id = `correct-${i}`
      const ta = row.querySelector('textarea')
      ta.name = `question[options][${i}]`
      ta.id = `question_options_${i}`
    })
  },

  _resetRows() {
    this._fromIdx = null
    this._lastTarget = null
    this.el.querySelectorAll('.opt-row').forEach(r => {
      r.style.transform = ''
      r.classList.remove('opacity-15', 'border-primary', 'bg-base-200')
    })
  },

  _cleanupClone() {
    if (this._clone) { this._clone.remove(); this._clone = null }
    if (this._onMove) { document.removeEventListener('mousemove', this._onMove); this._onMove = null }
    if (this._onUp) { document.removeEventListener('mouseup', this._onUp); this._onUp = null }
  },

  _cleanup() {
    this._cleanupClone()
    this._resetRows()
  }
}

let Dialog = {
  mounted() {
    this.el.showModal()
    this.el.addEventListener("close", () => {
      this.pushEvent(this.el.dataset.cancelEvent || "cancel_confirm")
    })
  },
  destroyed() {
    if (this.el.open) {
      this.el.close()
    }
  }
}

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
let liveSocket = new LiveSocket("/live", Socket, {
  params: { _csrf_token: csrfToken },
  hooks: { AutoDismiss, ImagePreview, CopyLink, ClipboardCopy, ScrollToBottom, OptionSorter, Dialog }
})

liveSocket.connect()
