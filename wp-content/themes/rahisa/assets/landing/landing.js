(() => {
  const landing = document.querySelector('.rahisa-landing');
  if (!landing) return;

  const menus = [...landing.querySelectorAll('[data-rahisa-menu]')];
  const closeMenus = (except) => {
    menus.forEach((menu) => {
      if (menu !== except) menu.open = false;
    });
  };

  menus.forEach((menu) => {
    menu.addEventListener('toggle', () => {
      if (menu.open) closeMenus(menu);
    });
    menu.addEventListener('click', (event) => {
      if (event.target.closest('a')) {
        menu.open = false;
        menu.querySelector('summary').focus({ preventScroll: true });
      }
    });
  });

  document.addEventListener('click', (event) => {
    if (!event.target.closest('[data-rahisa-menu]')) closeMenus();
    if (event.target.closest('a[href="#enrollment"]')) {
      const enrollment = landing.querySelector('#enrollment');
      if (!enrollment) return;
      enrollment.open = true;
      enrollment.querySelector('summary').focus({ preventScroll: true });
    }
  });

  document.addEventListener('keydown', (event) => {
    if (event.key !== 'Escape') return;
    const menu = menus.find((item) => item.open);
    if (!menu) return;
    menu.open = false;
    menu.querySelector('summary').focus();
  });
})();
