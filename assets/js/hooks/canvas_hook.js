const CanvasHook = {
  mounted() {
    this.handleEvent("update_canvas", ({ html }) => {
      this.el.innerHTML = html
      this.el.scrollTop = 0
    })

    this.handleEvent("lamp_loading", () => {
      this.el.innerHTML = `
        <div role="status" aria-label="Loading lamp" aria-live="polite"
             style="display:flex;align-items:center;justify-content:center;width:100%;padding:64px 24px;">
          <div class="ck-typing">
            <span></span><span></span><span></span>
          </div>
        </div>
      `
    })

    this.handleEvent("canvas_error", ({ reason }) => {
      this.el.innerHTML = `
        <div role="alert" aria-label="Error" aria-live="assertive"
             style="margin:auto;max-width:520px;padding:24px;text-align:center;">
          <div style="color:var(--danger);font-size:13.5px;line-height:1.55;">${reason}</div>
        </div>
      `
    })
  }
}

export default CanvasHook
