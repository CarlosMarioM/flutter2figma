# flutter2figma showcase

A dense, multi-screen Material 3 app used to stress-test flutter2figma:
a storefront, a product page, an analytics dashboard with a painted chart,
a chat, a profile with settings, a checkout form and a tabbed library.
It uses asset images, gradients, chips, list tiles, navigation bars,
segmented buttons, sliders, progress indicators and custom painters.

From the repository root:

```sh
tool/stress.sh
```

exports it statically and with `--runtime`, saves Flutter's own render of
every screen, and imports both designs through the Figma plugin's test mock.
The results land in `build/showcase/`; drop either `design.json` on the
Figma plugin to compare.
