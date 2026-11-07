#!/usr/bin/env python3
"""Genera los bloques 06 a 15 de la pasada de jugador (data/flows/jugador/): el día 2 (cartas y encargo de calidad), el
primer empleado y las medias jornadas de oficio de un novato (cartas, la mejora cuando se abre, pagar la deuda con oro
de sobra, encargos de espadas, hierro con recado, espadas en el yunque y venderlas). Los bloques 01-05 (el tutorial de
lo básico) se escriben a mano.

  python3 tools/verifica/jugador_bloques.py
"""
import json, os
D = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "data", "flows", "jugador")
def w(fid, title, about, steps):
    json.dump({"id": "jugador/" + fid, "title": title, "about": about, "start": {"keep": True}, "steps": steps},
              open(os.path.join(D, fid + ".json"), "w"), ensure_ascii=False, indent=2)

NOCH = "not q.shown({'within': 'UnlockCard', 'node': 'Button_chapter'})"
def cards(p):
    out = []
    for i in range(1, 4):
        out.append({"id": f"{p}carta_{i}", "say": "Una carta «Nuevo»: leerla y Entendido" if i == 1 else "",
                    "when": f"q.shown({{'within': 'UnlockCard', 'node': 'Button_ok'}}) and {NOCH}",
                    "click": {"within": "UnlockCard", "node": "Button_ok"}, "wait": 0.4})
    for i in range(1, 3):
        out.append({"id": f"{p}evento_{i}", "say": "Una carta de fiesta o de suceso: leerla y Entendido" if i == 1 else "",
                    "when": "q.shown({'within': 'EventCard', 'node': 'Button_ok'})",
                    "click": {"within": "EventCard", "node": "Button_ok"}, "wait": 0.4})
    return out

def chapter_from_card(p, chapter):
    return [{"id": f"{p}ver_capitulo", "say": f"La carta trae «Ver capítulo»: {chapter}",
             "when": f"q.shown({{'within': 'UnlockCard', 'node': 'Button_chapter'}}) and q.drv.node('UnlockCard').current == '{chapter}'",
             "click": {"within": "UnlockCard", "node": "Button_chapter"}, "until": f"q.tut().begins_with('{chapter}:')", "timeout": 6},
            {"id": f"{p}desde_ayuda", "say": f"Si no, F1 y el capítulo {chapter} desde la ayuda",
             "when": f"q.unlocked('{chapter}') and not q.chapter_done('{chapter}') and not q.tut().begins_with('{chapter}:')",
             "key": "F1", "expect": ["q.visible('HelpPanel')"]},
            {"id": f"{p}ayuda_capitulo", "when": "q.visible('HelpPanel')",
             "click": {"within": "HelpPanel", "node": f"Chapter_{chapter}"}, "until": f"q.tut().begins_with('{chapter}:')", "timeout": 6, "soft": True}]

def into_forge(p):
    return [{"id": f"{p}a_la_forja", "say": "A la forja", "when": "q.interior() != q.own('forge')",
             "world": {"own": "forge"}, "button": "right",
             "until": "q.interior() == q.own('forge') and q.location() == q.own('forge')", "timeout": 40}]

def leave(p):
    return [{"id": f"{p}cerrar_panel", "when": "q.visible('StoragePanel') or q.visible('ProductionPanel') or q.visible('StationMenu')", "key": "Escape"},
            {"id": f"{p}salir", "when": "q.interior() != ''", "click": {"node": "ExitButton"}, "until": "q.interior() == ''", "timeout": 20}]

def buy_iron(p, n=4):
    need = "q.storage('iron') < 4 and q.gold() >= 30"
    return leave(p + "s") + [{"id": f"{p}espera_mercado", "say": "De noche el puesto cierra: esperar a que abra (×4)",
             "when": need + " and not q.market_open('resources')", "key": "@speed_3", "until": "q.market_open('resources')", "timeout": 120}] + [{"id": f"{p}hierro_falta", "say": "Queda poco hierro: al puesto de Recursos con recado",
             "when": "q.storage('iron') < 4 and q.gold() >= 30",
             "world": {"service": "resources"}, "button": "right", "until": "q.visible('MarketPanel')", "timeout": 40},
            {"id": f"{p}hierro_mas", "say": "Tantos como dé el oro (4, u 8 con la bolsa llena)", "when": "q.visible('MarketPanel')", "click": {"within": {"within": "BuyList", "prefix": "iron_"}, "node": "Plus"}, "times": 3},
            {"id": f"{p}hierro_mas_8", "when": "q.visible('MarketPanel') and q.gold() >= 90", "click": {"within": {"within": "BuyList", "prefix": "iron_"}, "node": "Plus"}, "times": n - 4},
            {"id": f"{p}hierro_enviar", "when": "q.visible('MarketPanel')", "click": {"within": {"within": "BuyList", "prefix": "iron_"}, "node": "Send"}},
            {"id": f"{p}hierro_destino", "when": "q.visible('MarketPanel')", "popup": {"within": {"within": "BuyList", "prefix": "iron_"}, "node": "Send"}, "item": 0, "expect": ["q.order('buy')"], "soft": True},
            {"id": f"{p}hierro_reintento", "say": "El menú no cogió el clic: otra vez", "when": "q.visible('MarketPanel') and not q.order('buy')", "click": {"within": {"within": "BuyList", "prefix": "iron_"}, "node": "Send"}},
            {"id": f"{p}hierro_destino_2", "when": "q.visible('MarketPanel') and not q.order('buy')", "popup": {"within": {"within": "BuyList", "prefix": "iron_"}, "node": "Send"}, "item": 0, "soft": True},
            {"id": f"{p}carbon_mas", "when": "q.visible('MarketPanel') and q.storage('coal') < 3", "click": {"within": {"within": "BuyList", "prefix": "coal_"}, "node": "Plus"}, "times": 2},
            {"id": f"{p}carbon_enviar", "when": "q.visible('MarketPanel') and q.storage('coal') < 3", "click": {"within": {"within": "BuyList", "prefix": "coal_"}, "node": "Send"}},
            {"id": f"{p}carbon_destino", "when": "q.visible('MarketPanel') and q.storage('coal') < 3", "popup": {"within": {"within": "BuyList", "prefix": "coal_"}, "node": "Send"}, "item": 0},
            {"id": f"{p}cerrar_puesto", "when": "q.visible('MarketPanel')", "key": "Escape"}]

def forge_swords(p, n=2):
    return into_forge(p) + [
        {"id": f"{p}lingotes", "say": "Hacen falta lingotes (el aprendiz funde si tiene cola; si no, el horno a mano)",
         "when": "q.storage('iron_ingot') < 2 and not q.working('furnace') and q.storage('iron') >= 2", "station": "furnace", "button": "right", "expect": ["q.visible('StationMenu')"]},
        {"id": f"{p}lingotes_b", "when": "q.visible('StationMenu')", "click": {"via": "RecipeList", "fn": "get_node", "args": ["Row_forge_ingot"], "type": "Button"}},
        {"id": f"{p}x4", "say": "Mayús+3: ×4", "key": "@speed_3"},
        {"id": f"{p}espera_hierro", "say": "El recado del hierro tarda dos horas: esperar", "when": "q.storage('iron_ingot') < 2 and q.storage('iron') < 2 and q.deliveries() > 0", "until": "q.storage('iron') >= 2", "timeout": 60},
        {"id": f"{p}lingotes_2", "when": "q.storage('iron_ingot') < 2 and not q.working('furnace') and q.storage('iron') >= 2", "station": "furnace", "button": "right"},
        {"id": f"{p}lingotes_2b", "when": "q.visible('StationMenu')", "click": {"via": "RecipeList", "fn": "get_node", "args": ["Row_forge_ingot"], "type": "Button"}},
        {"id": f"{p}espera_lingotes", "say": "Esperar a dos lingotes", "when": "q.storage('iron_ingot') < 2 and (q.working('furnace') or q.storage('iron') >= 2)", "until": "q.storage('iron_ingot') >= 2", "timeout": 150, "soft": True},
        {"id": f"{p}yunque", "say": "El yunque: espadas en modo normal (se repite)", "when": "q.storage('iron_ingot') >= 2 and not q.working('anvil')", "station": "anvil", "button": "right", "expect": ["q.visible('StationMenu')"]},
        {"id": f"{p}normal", "when": "q.visible('StationMenu')", "click": {"node": "NormalButton"}},
        {"id": f"{p}espada", "when": "q.visible('StationMenu')", "click": {"via": "RecipeList", "fn": "get_node", "args": ["Row_forge_sword"], "type": "Button"}},
        {"id": f"{p}espera_espadas", "say": f"Esperar a {n} espadas", "when": "q.working('anvil') or q.storage('sword') > 0",
         "until": f"q.storage('sword') >= {n} or (not q.working('anvil') and q.storage('iron_ingot') < 2)", "timeout": 200},
        {"id": f"{p}almacen", "say": "Almacén: «Llevar productos»", "when": "q.storage('sword') > 0", "key": "@panel_storage", "expect": ["q.visible('StoragePanel')"]},
        {"id": f"{p}coger", "when": "q.visible('StoragePanel') and q.storage('sword') > 0", "click": {"node": "TakeButton"}, "until": "q.bag('sword') > 0", "timeout": 8},
    ] + leave(p)

def sell_swords(p):
    return [{"id": f"{p}espera_armeria", "say": "De noche la Armería cierra: esperar a que abra (×4)",
             "when": "q.bag('sword') > 0 and not q.market_open('armory')", "key": "@speed_3", "until": "q.market_open('armory')", "timeout": 120},
            {"id": f"{p}armeria", "say": "A la Armería a vender", "when": "q.bag('sword') > 0",
             "world": {"building": "armory"}, "button": "right", "until": "q.interior() == q.building('armory')", "timeout": 40},
            {"id": f"{p}mostrador", "when": "q.interior() == q.building('armory')", "station": "*", "button": "left", "until": "q.visible('MarketPanel')", "timeout": 8},
            {"id": f"{p}vender_tab", "when": "q.visible('MarketPanel')", "click": {"node": "SellTab"}},
            {"id": f"{p}vender_1", "say": "Vender las espadas, una a una (cada venta baja el precio)", "when": "q.visible('MarketPanel') and q.bag('sword') > 0",
             "click": {"within": {"within": "SellList", "prefix": "sword_"}, "node": "SellOne", "enabled": True}, "wait": 0.3, "soft": True},
            {"id": f"{p}vender_2", "when": "q.visible('MarketPanel') and q.bag('sword') > 0", "click": {"within": {"within": "SellList", "prefix": "sword_"}, "node": "SellOne", "enabled": True}, "wait": 0.3, "soft": True},
            {"id": f"{p}vender_3", "when": "q.visible('MarketPanel') and q.bag('sword') > 0", "click": {"within": {"within": "SellList", "prefix": "sword_"}, "node": "SellOne", "enabled": True}, "wait": 0.3, "soft": True},
            {"id": f"{p}vender_4", "when": "q.visible('MarketPanel') and q.bag('sword') > 0", "click": {"within": {"within": "SellList", "prefix": "sword_"}, "node": "SellOne", "enabled": True}, "wait": 0.3, "soft": True},
            {"id": f"{p}cerrar_mercado", "when": "q.visible('MarketPanel')", "key": "Escape"},
            {"id": f"{p}salir_armeria", "when": "q.interior() != ''", "click": {"node": "ExitButton"}, "until": "q.interior() == ''", "timeout": 20}]

def pay_debt(p):
    return [{"id": f"{p}pagar", "say": "Con oro de sobra, pagar la deuda en el libro (L → Deudas)",
             "when": "q.debt() > 0 and q.gold() >= q.debt() + 40 and q.interior() == ''", "key": "@ledger", "expect": ["q.visible('LedgerPanel')"]},
            {"id": f"{p}pagar_tab", "when": "q.visible('LedgerPanel')", "click": {"via": "LedgerPanel", "fn": "tab_button", "args": ["debts"]}},
            {"id": f"{p}pagar_todo", "when": "q.visible('LedgerPanel')", "click": {"within": "LedgerPanel", "node": "PayAll", "enabled": True},
             "until": "q.debt() == 0 or q.visible('ConfirmModal')", "timeout": 6, "soft": True},
            {"id": f"{p}pagar_si", "when": "q.visible('ConfirmModal')", "click": {"within": "ConfirmModal", "node": "ConfirmButton"}, "until": "q.debt() == 0", "timeout": 6},
            {"id": f"{p}cerrar_libro", "when": "q.visible('LedgerPanel')", "key": "Escape"}]

def board(p):
    return leave(p + "s") + [{"id": f"{p}tablon", "say": "Al tablón: ¿hay un encargo de espadas?", "when": "q.mine_id('sword') == ''",
             "world": {"service": "board"}, "button": "right", "until": "q.visible('BoardPanel')", "timeout": 40},
            {"id": f"{p}aceptar_espada", "when": "q.visible('BoardPanel') and q.board_id('sword') != ''", "click": {"within": {"node": "='Note_' + q.board_id('sword')"}, "node": "Accept", "enabled": True}, "soft": True},
            {"id": f"{p}cerrar", "when": "q.visible('BoardPanel')", "key": "Escape"}]


def deliver(p):
    return [{"id": f"{p}tablon", "say": "Entregar lo que pide el encargo aceptado", "when": "(q.mine_id('sword') != '' and q.bag('sword') > 0) or (q.mine_id('hammer') != '' and q.bag('hammer') > 0)",
             "world": {"service": "board"}, "button": "right", "until": "q.visible('BoardPanel')", "timeout": 40},
            {"id": f"{p}entregar", "when": "q.visible('BoardPanel') and q.mine_id('sword') != ''", "click": {"within": {"node": "='Row_' + q.mine_id('sword')"}, "node": "Deliver", "enabled": True}, "soft": True},
            {"id": f"{p}entregar_m", "when": "q.visible('BoardPanel') and q.mine_id('hammer') != ''", "click": {"within": {"node": "='Row_' + q.mine_id('hammer')"}, "node": "Deliver", "enabled": True}, "soft": True},
            {"id": f"{p}cerrar", "when": "q.visible('BoardPanel')", "key": "Escape"}]


# 06: cards + the quality contract
w("06_calidad", "Jugador 6 · Las cartas «Nuevo» y un encargo de calidad buena",
  "Día 2, con la fiesta: las cartas que se juntaron y el objetivo de un encargo de calidad «buena»: la espada del capitán, forjada a mano.",
  cards("a_") + [
    {"id": "objetivo", "say": "El objetivo: un encargo de calidad buena", "expect": ["q.has_text('calidad')"], "soft": True},
    {"id": "tablon", "say": "Al tablón", "world": {"service": "board"}, "button": "right", "until": "q.visible('BoardPanel')", "timeout": 40},
    {"id": "aceptar_espada", "say": "La espada «calidad buena o mejor» del capitán", "when": "q.board_id('sword') != ''", "click": {"within": {"node": "='Note_' + q.board_id('sword')"}, "node": "Accept"}, "expect": ["q.order('accept_contract')"]},
    {"id": "esc_tablon", "key": "Escape"}] + buy_iron("b_") + into_forge("c_") + [
    {"id": "horno", "say": "Dos lingotes en el horno", "when": "q.storage('iron_ingot') < 2", "station": "furnace", "button": "right", "expect": ["q.visible('StationMenu')"]},
    {"id": "horno_b", "when": "q.visible('StationMenu')", "click": {"via": "RecipeList", "fn": "get_node", "args": ["Row_forge_ingot"], "type": "Button"}},
    {"id": "x4", "key": "@speed_3"},
    {"id": "espera_lingotes", "when": "q.storage('iron_ingot') < 2", "until": "q.storage('iron_ingot') >= 2", "timeout": 150},
    {"id": "yunque", "say": "El yunque en Forja viva", "station": "anvil", "button": "right", "expect": ["q.visible('StationMenu')"]},
    {"id": "viva", "click": {"node": "CarefulButton"}},
    {"id": "espada", "click": {"via": "RecipeList", "fn": "get_node", "args": ["Row_forge_sword"], "type": "Button"}, "until": "q.live_open()", "timeout": 30},
    {"id": "calentar", "until": "q.live_heat_ok()", "timeout": 30},
    {"id": "sacar", "click": {"node": "PullButton"}},
    {"id": "golpe_espera", "until": "q.live_stage() == 'strike'", "timeout": 8}] + [
    {"id": f"golpe_{i}", "when": "q.live_stage() == 'strike'", "click": {"node": "='Strike_' + q.live_strike()"}} for i in range(1, 7)] + [
    {"id": "templar_espera", "until": "q.live_stage() == 'quench'", "timeout": 8},
    {"id": "templar", "click": {"node": "='Quench_' + q.live_quench()"}},
    {"id": "resultado", "say": "La pieza termina sola", "until": "q.storage('sword') > 0", "timeout": 90},
    {"id": "cerrar_viva", "when": "q.live_open()", "click": {"within": "LiveForgeScreen", "node": "CloseButton"}},
    {"id": "esc_menu", "when": "q.visible('StationMenu')", "key": "Escape"},
    {"id": "almacen", "key": "@panel_storage", "expect": ["q.visible('StoragePanel')"]},
    {"id": "coger", "click": {"within": "BuildingGrid", "prefix": "sword_"}, "until": "q.bag('sword') > 0", "timeout": 8}] + leave("d_") + [
    {"id": "tablon_2", "world": {"service": "board"}, "button": "right", "until": "q.visible('BoardPanel')", "timeout": 40},
    {"id": "entregar", "say": "Entregar la espada de calidad", "when": "q.mine_id('sword') != ''", "click": {"within": {"node": "='Row_' + q.mine_id('sword')"}, "node": "Deliver"}, "expect": ["q.order('deliver_contract')"], "soft": True},
    {"id": "esc_tablon_2", "key": "Escape"}])

# 07: the staff chapter when it opens (earning meanwhile)
w("07_empleado", "Jugador 7 · El primer empleado",
  "Cuando abre Empleados (150 de oro o 3 encargos): su carta «Ver capítulo» (o F1), contratar un aprendiz y ponerle la cola de lingotes. Mientras no abre, forjar y vender.",
  cards("a_") + [{"id": "abierto", "say": "¿Ya se abrió Empleados?", "expect": ["q.unlocked('staff') or true"]}] +
  [dict(s, when="not q.unlocked('staff')" + (" and (" + s["when"] + ")" if "when" in s else "")) for s in forge_swords("w_") + sell_swords("v_")] +
  cards("b_") + chapter_from_card("s_", "staff") + [
    {"id": "gestionar", "when": "q.tut() == 'staff:manage'", "world": {"own": "forge"}, "double": True, "until": "q.tut() != 'staff:manage'", "timeout": 10},
    {"id": "empleados", "when": "q.tut() == 'staff:open'", "key": "@panel_staff", "until": "q.tut() != 'staff:open'", "timeout": 4},
    {"id": "plantilla", "when": "q.tut() == 'staff:staff_tab'", "click": {"via": "Tutorial", "node": "Button_next"}, "until": "q.tut() != 'staff:staff_tab'", "timeout": 4},
    {"id": "contratar_tab", "when": "q.tut() == 'staff:hire_tab'", "click": {"node": "HireTab"}, "until": "q.tut() != 'staff:hire_tab'", "timeout": 4},
    {"id": "rangos", "when": "q.tut() == 'staff:ranks'", "click": {"via": "Tutorial", "node": "Button_next"}, "until": "q.tut() != 'staff:ranks'", "timeout": 4},
    {"id": "lista", "when": "q.tut() == 'staff:list'", "click": {"via": "Tutorial", "node": "Button_next"}, "until": "q.tut() != 'staff:list'", "timeout": 4},
    {"id": "contratar_1", "say": "Contratar (la meta lo pide): primer clic", "when": "q.visible('StaffPanel')", "click": {"within": "StaffPanel", "node": "Hire"}},
    {"id": "contratar_2", "say": "Segundo clic: contratado", "when": "q.visible('StaffPanel')", "click": {"within": "StaffPanel", "node": "Hire"}, "until": "q.staff('forge') > 0", "timeout": 6, "expect": ["q.order('hire')"]},
    {"id": "produccion", "key": "@panel_production", "expect": ["q.visible('ProductionPanel')"]},
    {"id": "cola_tab", "click": {"node": "QueueTab"}},
    {"id": "receta", "click": {"within": "RecipeGrid", "node": "forge_ingot"}},
    {"id": "anadir", "click": {"node": "Add5"}, "until": "q.queue_len('forge') > 0", "timeout": 6, "expect": ["q.order('queue_add')"]},
    {"id": "bucle", "click": {"node": "LoopButton"}, "expect": ["q.order('queue_loop')"]},
    {"id": "anadir_tut", "when": "q.tut() == 'staff:add'", "click": {"via": "Tutorial", "node": "Button_next"}, "until": "q.tut() == 'staff:end'", "timeout": 4},
    {"id": "cerrar_tut", "when": "q.tut() != ''", "click": {"via": "Tutorial", "node": "Button_close"}},
    {"id": "esc", "when": "q.visible('ProductionPanel')", "key": "Escape"}])

# 08-15: half days of play
for n in range(8, 16):
    p = ""
    steps = cards("a_") + chapter_from_card("m_", "upgrades") + [
        {"id": "mejoras_gestionar", "when": "q.tut() == 'upgrades:manage'", "world": {"own": "forge"}, "double": True, "until": "q.tut() != 'upgrades:manage'", "timeout": 10},
        {"id": "mejoras_abrir", "when": "q.tut() == 'upgrades:open'", "key": "@panel_upgrades", "until": "q.tut() != 'upgrades:open'", "timeout": 4},
        {"id": "mejoras_rejilla", "when": "q.tut() == 'upgrades:grid'", "click": {"via": "Tutorial", "node": "Button_next"}, "until": "q.tut() != 'upgrades:grid'", "timeout": 4},
        {"id": "mejoras_detalle", "when": "q.tut() == 'upgrades:detail'", "click": {"via": "Tutorial", "node": "Button_next"}, "until": "q.tut() != 'upgrades:detail'", "timeout": 4},
        {"id": "mejoras_comprar", "when": "q.tut() == 'upgrades:buy'", "click": {"via": "Tutorial", "node": "Button_next"}, "until": "q.tut() != 'upgrades:buy'", "timeout": 4},
        {"id": "mejora_compra", "say": "Comprar la mejora que propone el detalle (la meta lo pide)", "when": "q.visible('UpgradePanel') and q.shown({'within': 'UpgradePanel', 'node': 'BuyButton', 'enabled': true})",
         "click": {"within": "UpgradePanel", "node": "BuyButton"}, "until": "q.order('buy_upgrade') or q.visible('ConfirmModal')", "timeout": 4, "soft": True},
        {"id": "mejora_si", "when": "q.visible('ConfirmModal')", "click": {"within": "ConfirmModal", "node": "ConfirmButton"}},
        {"id": "mejoras_fin", "when": "q.tut().begins_with('upgrades:')", "click": {"via": "Tutorial", "node": "Button_close"}, "soft": True},
        {"id": "mejoras_esc", "when": "q.visible('UpgradePanel')", "key": "Escape"},
    ] + pay_debt("d_") + board("t_") + buy_iron("h_", 8) + forge_swords("f_") + deliver("e_") + sell_swords("v_") + [
        {"id": "pasa_el_dia", "say": "Sin nada más que hacer, el reloj corre (×4) hasta la siguiente media jornada", "key": "@speed_3",
         "until": "q.minute() >= q.was('minute') + 360", "timeout": 90},
        {"id": "fin", "say": "Fin de la media jornada: el reloj", "expect": ["q.day() >= 0"]}]
    w(f"{n:02d}_jornada", f"Jugador {n} · Media jornada de oficio",
      "El oficio de cada día como lo juega un novato: las cartas que llegan, la mejora cuando se abre, pagar la deuda con oro de sobra, hierro con recado, espadas en el yunque y venderlas en la Armería.",
      steps)
print("ok")
