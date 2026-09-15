import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["pill", "link"]
  static values = { level: { type: String, default: "mixed" } }

  connect() {
    this.updateLinks()
  }

  pick(e) {
    this.levelValue = e.currentTarget.dataset.level
    this.pillTargets.forEach((pill) => {
      pill.classList.toggle("is-active", pill.dataset.level === this.levelValue)
      pill.setAttribute("aria-pressed", pill.dataset.level === this.levelValue ? "true" : "false")
    })
    this.updateLinks()
  }

  updateLinks() {
    this.linkTargets.forEach((link) => {
      const url = new URL(link.href, window.location.origin)
      url.searchParams.set("level", this.levelValue)
      link.href = url.pathname + url.search
    })
  }
}
