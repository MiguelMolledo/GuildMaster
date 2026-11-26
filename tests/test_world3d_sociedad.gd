extends "res://tests/test_case.gd"
## The family in the 3D town (docs/3d/repaso_sociedad.md): the bodies keep the 2D's rules of identity. The white the
## palette keeps for age (data/view.json portraits.aged_hair) is drawn with the natural tone, as the portraits do
## (Identity.natural_hair): the children of family_ages, who inherit their mother's white in the data, get no white
## hair; the grey of the old comes from the age profile (CharBuilder, kit.ages).

var cat := Catalog.load_from()


func test_no_white_hair_before_its_time() -> void:
	var r := NewGame.from_scenario("family_ages")
	var t := Town3D.new()
	t.setup(Sim.new(r["state"], cat))
	var st: WorldState = t.sim.state
	var aged: Dictionary = (ViewConfig.value("portraits", {}) as Dictionary).get("aged_hair", {})
	var kids := 0
	for id: String in ["chr_0019", "chr_0020", "chr_0021", "chr_0022"]:   # Pere 16, Clara 12, Elvira 8, Jordi 0
		var vis: Dictionary = st.characters[id].get("visual", {})
		if aged.has(str(int(vis.get("hair", -1)))):
			kids += 1
		var d: Dictionary = t._def_for(id, t.trace.characters[id])
		check(str((d["paint"] as Dictionary).get("hair", "")) != "white", "%s (%d): no white hair" % [id, int(d.get("age", -1))])
	check(kids > 0, "the scenario still has a child with the aged tone in the data (else the test proves nothing)")
	var hugo: Dictionary = t._def_for("chr_0001", t.trace.characters["chr_0001"])
	check(float(CharBuilder.age_profile(hugo).get("grey", 0.0)) > 0.5, "Hugo (62): grey from his age")
	t.free()
