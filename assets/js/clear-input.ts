// Clearable search inputs: a <button data-clear-input> sitting next to an
// <input> clears the field and re-dispatches `input` so the surrounding
// phx-change form resets the LiveView filter. Escape inside the input does
// the same. The button's visibility is pure CSS (peer-[:not(:placeholder-shown)]).

const clearInput = (input: HTMLInputElement): void => {
  if (input.value === "") return
  input.value = ""
  input.dispatchEvent(new Event("input", { bubbles: true }))
  input.focus()
}

const siblingInput = (el: HTMLElement): HTMLInputElement | null =>
  el.parentElement?.querySelector("input") ?? null

document.addEventListener("click", (e: Event) => {
  const btn = (e.target as HTMLElement).closest<HTMLElement>("[data-clear-input]")
  if (!btn) return
  const input = siblingInput(btn)
  if (input) clearInput(input)
})

document.addEventListener("keydown", (e: Event) => {
  if ((e as KeyboardEvent).key !== "Escape") return
  const target = e.target
  if (!(target instanceof HTMLInputElement)) return
  if (!target.parentElement?.querySelector("[data-clear-input]")) return
  clearInput(target)
})
