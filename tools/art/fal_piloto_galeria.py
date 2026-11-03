#!/usr/bin/env python3
"""Galería HTML del piloto de fal: cada pieza cruda (miniatura) frente a la procesada, a tamaño real y ampliada con
vecino más cercano (CSS image-rendering: pixelated). Imágenes incrustadas en base64.

Uso: python3 tools/art/fal_piloto_galeria.py -> assets/art/fal_piloto/galeria.html
"""
import base64
import html
import io
import json
import os
import sys

from PIL import Image

HERE = os.path.dirname(__file__)
sys.path.insert(0, HERE)
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
import fal_rutas as fr_  # noqa: E402  (crudos fuera del repo)
D = fr_.PILOTO
GUILD = os.path.expanduser("~/Code/guild/assets/sprites")


def b64(path_or_im, thumb=0, fmt=None):
    im = Image.open(path_or_im) if isinstance(path_or_im, str) else path_or_im
    buf = io.BytesIO()
    if thumb:
        im = im.convert("RGB")
        im.thumbnail((thumb, thumb * 2), Image.LANCZOS)
        im.save(buf, "JPEG", quality=60)
        mime = "jpeg"
    elif fmt == "gif":
        with open(path_or_im, "rb") as f:
            buf.write(f.read())
        mime = "gif"
    else:
        rgba = im.convert("RGBA")
        cols = rgba.getcolors(256)
        if cols and rgba.getchannel("A").getextrema()[0] == 255:
            im = rgba.convert("RGB").quantize(colors=len(cols), method=Image.Quantize.FASTOCTREE,
                                               dither=Image.Dither.NONE)  # ya son ≤256 colores: exacto
        im.save(buf, "PNG", optimize=True)
        mime = "png"
    return f"data:image/{mime};base64," + base64.b64encode(buf.getvalue()).decode()


def p(*parts):
    return fr_.piloto(*parts)


URIS = {}


def ref(path, thumb=0):
    """Cada imagen se incrusta una sola vez (mapa en JS) aunque salga a varios tamaños."""
    key = f"{path}|{thumb}"
    if key not in URIS:
        URIS[key] = (len(URIS), b64(path, thumb) if thumb else b64(path, fmt="gif" if str(path).endswith(".gif") else None))
    return URIS[key][0]


def img(path, z=1, cap="", thumb=0, checker=False):
    if not os.path.exists(path) if isinstance(path, str) else False:
        return f"<figure><div class='miss'>falta {html.escape(os.path.relpath(path, ROOT))}</div></figure>"
    if thumb:
        k = ref(path, thumb)
        style = f"width:{thumb}px"
    else:
        im = Image.open(path)
        k = ref(path)
        style = f"width:{im.width * z}px;height:{im.height * z}px"
    cls = "px" + (" chk" if checker else "")
    return (f"<figure><img class='{cls}' style='{style}' data-k='{k}'>"
            f"<figcaption>{html.escape(cap)}</figcaption></figure>")


def row(*cells):
    return "<div class='row'>" + "".join(cells) + "</div>"


def guild_portrait_64():
    im = Image.open(os.path.join(GUILD, "ui", "portraits", "portrait_artesano.png")).convert("RGBA")
    return im.resize((64, 64), Image.BOX)


def section(title, verdict, body):
    return f"<section><h2>{html.escape(title)}</h2><p class='v'>{verdict}</p>{body}</section>"


def main():
    led = [r for r in json.load(open(p("gasto.json"))) if r.get("tanda", "piloto") == "piloto"]
    by = {}
    for r in led:
        by[r["pieza"]] = by.get(r["pieza"], 0) + r["usd"]
    total = sum(by.values())
    tmp = p("_refs", "guild_artesano_64.png")
    guild_portrait_64().save(tmp)

    s = []
    # 1. retratos
    people = ["artesano", "artesana", "anciano", "rival", "nina", "trabajador", "anciana", "rival_esposa"]
    body = row(img(p("retratos", "crudo", "grid_nano_v1.png"), thumb=300, cap="crudo · nano-banana (0,04)"),
               img(p("retratos", "crudo", "grid_nano2_v1.png"), thumb=300, cap="crudo · nano-banana-2 (0,08)"),
               img(p("retratos", "crudo", "grid2_nano2_v1.png"), thumb=300,
                   cap="crudo · 2ª tanda nano-banana-2, ref = la 1ª"),
               img(p("_refs", "retratos_guild.png"), thumb=300, cap="referencia de estilo: Guild Renew"))
    body += "<h3>64×64 (fichas y cartas) · real y ×4</h3>" + row(
        *[img(p("retratos", "final", f"nano2_{n}_64.png"), 1, n) for n in people])
    body += row(*[img(p("retratos", "final", f"nano2_{n}_64.png"), 4, n) for n in people[:4]])
    body += row(*[img(p("retratos", "final", f"nano2_{n}_64.png"), 4, n) for n in people[4:]])
    body += "<h3>32×32 (HUD) · real y ×4 · recorte de cara</h3>" + row(
        *[img(p("retratos", "final", f"nano2_{n}_32.png"), 1, n) for n in people])
    body += row(*[img(p("retratos", "final", f"nano2_{n}_32.png"), 4, n) for n in people])
    body += "<h3>Pixelado: local (Pillow, caja + 32 colores) frente a image2pixel</h3>" + row(
        img(p("retratos", "local", "nano2_artesano_64.png"), 4, "local · caja"),
        img(p("retratos", "final", "nano2_artesano_64.png"), 4, "image2pixel · escala 8"),
        img(p("retratos", "local", "nano2_artesano_32.png"), 4, "local 32"),
        img(p("retratos", "final", "nano2_artesano_32.png"), 4, "image2pixel 32"),
        img(tmp, 4, "Guild Renew /3 (comparación)"))
    body += "<h3>Identidad de familia (GDD 4.10.9) sobre un retrato de fal</h3>" + row(
        img(p("retratos", "final", "nano2_artesano_64_familias.png"), 3,
            "regiones (pelo, piel, ropa 1 y 2) y 3 familias con el mismo intercambio que el shader"))
    s.append(section("1 · Retratos", "<b>Sirve.</b> Mismo estilo entre tandas con la rejilla anterior como "
                     "referencia; image2pixel a 64 da contornos limpios. A 32 se leen con recorte de cara "
                     "(edad, género y pelo), no los detalles. Los colores clave se pueden codificar después "
                     "(barba y labios necesitan repaso).", body))
    # 2. título
    body = row(img(p("titulo", "crudo", "titulo_alba_v1.png"), thumb=320, cap="crudo alba · nano-banana-2"),
               img(p("titulo", "crudo", "titulo_noche_v1.png"), thumb=320, cap="crudo noche · edit del alba"))
    body += "<h3>480×270 mostrado ×2 = 960×540, como en el viewport (noche con el logotipo del kit)</h3>"
    body += row(img(p("titulo", "final", "titulo_noche_v1_480_con_logo.png"), 2, "noche + logo"))
    body += row(img(p("titulo", "final", "titulo_alba_v1_480.png"), 2, "alba · caja + paleta de image2pixel"))
    for k, n in (("local", "local caja + 48 colores"), ("final", "caja + paleta de image2pixel")):
        Image.open(p("titulo", k, "titulo_alba_v1_480.png")).crop((150, 90, 330, 190)).save(p("_refs", f"crop_{k}.png"))
    body += row(img(p("_refs", "crop_local.png"), 4, "recorte ×4 · local caja + 48 colores"),
                img(p("_refs", "crop_final.png"), 4, "recorte ×4 · caja + paleta de image2pixel"))
    s.append(section("2 · Fondo de la pantalla de título", "<b>Sirve.</b> El cielo deja hueco al logotipo; la "
                     "versión de noche sale con edit sobre la de alba (misma ciudad). Reducido a 480×270 y "
                     "escalado ×2 entero queda nítido.", body))
    # 3. eventos
    body = row(img(p("eventos", "crudo", "guerra_v1.png"), thumb=320, cap="crudo guerra"),
               img(p("eventos", "crudo", "fiesta_v1.png"), thumb=320, cap="crudo fiesta"))
    body += "<h3>240×135 · real y ×4</h3>" + row(img(p("eventos", "final", "guerra_v1_240.png"), 1, "guerra"),
                                                 img(p("eventos", "final", "fiesta_v1_240.png"), 1, "fiesta"),
                                                 )
    body += row(img(p("eventos", "final", "guerra_v1_240.png"), 4, "guerra ×4"))
    body += row(img(p("eventos", "final", "fiesta_v1_240.png"), 4, "fiesta ×4"))
    s.append(section("3 · Ilustraciones de evento", "<b>Sirve.</b> Propuesta: 240×135 para el libro y las cartas "
                     "(cabe en una carta de 380 con margen) y 192×108 para el aviso. Con la lámina de título "
                     "como referencia, el estilo de las dos casa.", body))
    # 4. iconos
    ic = ["sierra", "arcon", "estatua", "acero"]
    gr = ["martillo", "sierra", "espada", "lingote_hierro"]
    body = row(img(p("iconos", "crudo", "iconos_v1.png"), thumb=300, cap="crudo · 4 iconos en una imagen"),
               img(p("_refs", "iconos_guild_x4.png"), thumb=300, cap="referencia: iconos de Guild Renew"))
    body += "<h3>32×32 · real</h3>" + row(*[img(p("iconos", "final", f"{n}_32.png"), 1, n, checker=True) for n in ic])
    body += "<h3>×4: fal + image2pixel · fal local (caja) · Guild Renew</h3>"
    body += row(*[img(p("iconos", "final", f"{n}_32.png"), 4, n + " (i2p)", checker=True) for n in ic])
    body += row(*[img(p("iconos", "local", f"{n}_32_caja.png"), 4, n + " (local)", checker=True) for n in ic])
    body += row(*[img(os.path.join(GUILD, "ui", "icons", f"icon_{n}.png"), 4, "Guild Renew " + n, checker=True)
                  for n in gr])
    s.append(section("4 · Iconos de objeto 32×32", "<b>Sirve con retoque.</b> Limpios y legibles, pero más planos "
                     "y de contorno más grueso que los de Guild Renew; la estatua queda pequeña. Hay que "
                     "igualar tamaño y contorno a mano (pixelart_workbench) para que casen en la misma rejilla.",
                     body))
    # 5. fachada
    chr_frame = Image.open(p("_refs", "townsfolk_walk_se.png")).crop((0, 0, 68, 68))
    chr_path = p("_refs", "townsfolk_frame.png")
    chr_frame.save(chr_path)
    body = row(*[img(p("fachada", "crudo", f"{n}.png"), thumb=260, cap=c) for n, c in
                 (("sastreria_v1", "v1 nano-banana-2 (refs armería + casa)"),
                  ("sastreria_v2", "v2 nano-banana-2 (solo armería)"),
                  ("sastreria_pro_v1", "v1 nano-banana-pro (solo armería)"))])
    body += "<h3>192×192, mismo ancho y suelo que armory.png · ×2</h3>" + row(
        img(p("fachada", "final", "sastreria_v2_192.png"), 2, "v2 nano2 + image2pixel", checker=True),
        img(p("fachada", "final", "sastreria_pro_v1_192.png"), 2, "pro + image2pixel", checker=True),
        img(os.path.join(ROOT, "assets", "art", "buildings", "armory.png"), 2, "armory.png (juego)", checker=True),
        img(chr_path, 2, "vecino 68×68 (escala)", checker=True))
    body += row(img(p("fachada", "final", "sastreria_pro_v1_192.png"), 1, "pro, real", checker=True),
                img(p("fachada", "local", "sastreria_pro_v1_192.png"), 1, "pro, local", checker=True),
                img(p("fachada", "final", "sastreria_v1_192.png"), 1, "v1 (proyección mala)", checker=True))
    s.append(section("5 · Fachada de la Sastrería", "<b>Sirve con retoque.</b> Con la armería como única "
                     "referencia respeta la proyección 2:1, el suelo y la altura (v1, con dos referencias, se "
                     "fue a una torre). Pro sale más limpia y casi calca la armería; nano-banana-2 es más "
                     "propia. Sin letras en el cartel. Falta repasar el borde y la sombra.", body))
    # 6. paseo
    body = row(*[img(p("paseo", "crudo", f"{n}.png"), thumb=260, cap=c) for n, c in
                 (("paseo_v1", "v1 nano2, fondo verde"), ("paseo_v2", "v2 nano2, fondo blanco"),
                  ("paseo_pro_v1", "pro, fondo blanco"))])
    body += "<h3>Animado ×4 (150 ms por fotograma) frente al del juego</h3>" + row(
        img(p("paseo", "final", "paseo_v1_i2p.gif"), 1, "v1"), img(p("paseo", "final", "paseo_v2_i2p.gif"), 1, "v2"),
        img(p("paseo", "final", "paseo_pro_v1_i2p.gif"), 1, "pro"),
        img(p("paseo", "final", "referencia_juego.gif"), 1, "juego (PixelLab, 6 fotogramas)"))
    body += "<h3>Tiras 68×68 · ×3</h3>" + "".join(
        row(img(p("paseo", "final", f"{n}_tira_i2p.png"), 3, n, checker=True)) for n in
        ("paseo_v1", "paseo_v2", "paseo_pro_v1"))
    body += row(img(p("_refs", "townsfolk_walk_se.png"), 3, "referencia del juego", checker=True))
    s.append(section("6 · Experimento de animación (paseo de 4 fotogramas)", "<b>No sirve.</b> El personaje se "
                     "parece, pero los fotogramas no forman un ciclo: dos poses casi iguales, el tamaño baila "
                     "(41-49 px de alto) y el giro de la diagonal varía; Pro tampoco lo arregla. El verde deja "
                     "motas al pixelar y birefnet deja bordes semitransparentes. El fondo blanco se recorta limpio; la transparencia no es el problema, la "
                     "coherencia sí.", body))

    costs = "".join(f"<tr><td>{html.escape(k)}</td><td>{v:.3f}</td></tr>" for k, v in by.items())
    page = f"""<!doctype html><html lang="es"><meta charset="utf-8"><title>Piloto de arte fal</title>
<style>
body{{background:#1a1209;color:#ece4d2;font:14px/1.45 system-ui,sans-serif;margin:24px;max-width:1500px}}
h1{{color:#f2d880}} h2{{color:#c8a84e;border-bottom:1px solid #8a7032;padding-bottom:4px;margin-top:40px}}
h3{{color:#a89878;font-size:13px;font-weight:600;margin:18px 0 6px}}
.v{{background:#2a1f14;border-left:3px solid #c8a84e;padding:8px 12px}}
.row{{display:flex;flex-wrap:wrap;gap:14px;align-items:flex-end;margin:6px 0}}
figure{{margin:0}} figcaption{{font-size:11px;color:#a89878;max-width:420px}}
img.px{{image-rendering:pixelated;display:block}}
img.chk{{background:repeating-conic-gradient(#3e2814 0 25%,#5c3a1e 0 50%) 0 0/16px 16px}}
table{{border-collapse:collapse}} td,th{{border:1px solid #5c3a1e;padding:3px 10px}}
</style>
<h1>Piloto de arte con fal.ai · GuildMaster</h1>
<p>2026-11-03 · rama <code>arte-fal</code> · ficheros en <code>assets/art/fal_piloto/</code> · gasto
<b>{total:.2f} USD</b> de un tope de 3. Las ampliaciones son con vecino más cercano.</p>
<table><tr><th>Pieza</th><th>USD</th></tr>{costs}<tr><th>Total</th><th>{total:.3f}</th></tr></table>
{''.join(s)}
<script>const U={json.dumps({v[0]: v[1] for v in URIS.values()})};
document.querySelectorAll('img[data-k]').forEach(i=>i.src=U[i.dataset.k]);</script>
</html>"""
    out = p("galeria.html")
    with open(out, "w") as f:
        f.write(page)
    print(out, round(len(page) / 1024), "KB")


if __name__ == "__main__":
    main()
