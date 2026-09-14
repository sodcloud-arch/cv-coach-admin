/* CV Coach Admin Bootstrap — V78 preserved + V92 + V93 + V94 + V95 + V96 modules */
(() => {
  const load = (id, src, onload) => {
    const existing = document.getElementById(id);
    if (existing) {
      if (typeof onload === 'function') onload();
      return;
    }
    const script = document.createElement('script');
    script.id = id;
    script.src = src;
    script.async = false;
    if (typeof onload === 'function') script.onload = onload;
    script.onerror = () => console.error('CV Coach admin asset failed:', src);
    document.head.appendChild(script);
  };

  load('cv-v78-library-original-script', '/admin-assets/v78-library-original.js', () => {
    load('cv-v92-cutover-script', '/admin-assets/cv12-cutover-admin-v92.js', () => {
      load('cv-v93-lifecycle-script', '/admin-assets/client-lifecycle-admin-v93.js', () => {
        load('cv-v94-coach-ai-script', '/admin-assets/coach-ai-command-center-v94.js', () => {
          load('cv-v95-action-workspace-script', '/admin-assets/coach-action-workspace-v95.js', () => {
            load('cv-v96-outcome-intelligence-script', '/admin-assets/coach-outcome-intelligence-v96.js');
          });
        });
      });
    });
  });
})();
