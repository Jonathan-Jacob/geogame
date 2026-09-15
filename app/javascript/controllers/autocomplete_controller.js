import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "list"]
  static values = { url: String }

  connect() {
    this.countries = []
    this.filtered = []
    this.activeIndex = -1
    this.fetchCountries()
    requestAnimationFrame(() => this.inputTarget.focus())
    this.inputTarget.addEventListener("input", () => this.onInput())
    this.inputTarget.addEventListener("keydown", (e) => this.onKeydown(e))
    document.addEventListener("click", (e) => {
      if (!this.element.contains(e.target)) this.hide()
    })
  }

  async fetchCountries() {
    try {
      const res = await fetch(this.urlValue, { headers: { Accept: "application/json" } })
      this.countries = await res.json()
    } catch (e) {
      this.countries = []
    }
  }

  onInput() {
    const q = this.normalize(this.inputTarget.value)
    if (q.length < 3) return this.hide()
    this.filtered = this.countries
      .filter((c) => this.normalize(c.name).includes(q))
      .slice(0, 8)
    this.activeIndex = this.filtered.length > 0 ? 0 : -1
    this.render()
  }

  onKeydown(e) {
    if (e.key === "ArrowDown") { e.preventDefault(); this.move(1) }
    else if (e.key === "ArrowUp") { e.preventDefault(); this.move(-1) }
    else if (e.key === "Enter") {
      if (this.activeIndex >= 0 && this.filtered[this.activeIndex]) {
        e.preventDefault()
        this.choose(this.filtered[this.activeIndex])
      }
      this.element.requestSubmit()
    } else if (e.key === "Escape") this.hide()
  }

  move(dir) {
    if (!this.filtered.length) return
    this.activeIndex = (this.activeIndex + dir + this.filtered.length) % this.filtered.length
    this.render()
  }

  choose(country) {
    this.inputTarget.value = country.name
    this.hide()
  }

  render() {
    if (!this.filtered.length) return this.hide()
    this.listTarget.innerHTML = this.filtered.map((c, i) => `
      <li><button type="button" data-action="click->autocomplete#pick" data-index="${i}"
        class="w-full text-left px-4 py-2.5 cursor-pointer ${i === this.activeIndex ? "bg-indigo-100" : "hover:bg-amber-50"}">
        ${this.escape(c.name)}
      </button></li>`).join("")
    this.listTarget.classList.remove("hidden")
  }

  pick(e) {
    const country = this.filtered[Number(e.currentTarget.dataset.index)]
    if (country) this.choose(country)
    this.inputTarget.focus()
  }

  hide() {
    this.listTarget.classList.add("hidden")
    this.listTarget.innerHTML = ""
  }

  normalize(s) {
    return (s || "").toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "").trim()
  }

  escape(s) {
    return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;")
  }
}
