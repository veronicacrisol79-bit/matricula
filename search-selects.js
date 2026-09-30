/* Mejora los selectores nativos sin cambiar el modelo de datos de Alpine. */
(() => {
  if (!window.TomSelect) return;
  let scheduled = false;
  const signature = select => [...select.options].map(o => `${o.value}\u0000${o.textContent}`).join('\u0001');
  const sync = () => {
    scheduled = false;
    document.querySelectorAll('select').forEach(select => {
      const options = signature(select);
      if (!select.tomselect) {
        new window.TomSelect(select, {
          create: false,
          maxOptions: 500,
          searchField: ['text'],
          sortField: [{ field: 'text', direction: 'asc' }],
          render: { no_results: () => '<div class="no-results">Sin coincidencias</div>' }
        });
      } else if (select.dataset.optionSignature !== options) {
        select.tomselect.sync();
      }
      select.dataset.optionSignature = options;
      if (select.tomselect.getValue() !== select.value) select.tomselect.setValue(select.value, true);
    });
  };
  const schedule = () => {
    if (scheduled) return;
    scheduled = true;
    requestAnimationFrame(sync);
  };
  document.addEventListener('alpine:initialized', () => {
    schedule();
    new MutationObserver(mutations => {
      if (mutations.some(m => m.target.tagName === 'SELECT' || m.target.tagName === 'OPTION'
        || [...m.addedNodes].some(node => node.nodeType === 1 && (node.tagName === 'SELECT' || node.querySelector?.('select'))))) schedule();
    }).observe(document.body, { childList: true, subtree: true, characterData: true });
  });
  window.syncSearchableSelects = schedule;
})();
