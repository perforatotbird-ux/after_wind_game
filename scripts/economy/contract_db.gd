class_name ContractDB
extends RefCounted

## Реестр контрактов и заказов поселений (Этап 7, разделы 22, 23, 86)

const ItemDB = preload("res://scripts/inventory/item_db.gd")

const CONTRACTS: Array[Dictionary] = [
	{
		"id": "contract_fortify",
		"title": "Первичное укрепление времянки",
		"client": "Беженцы у холма",
		"description": "После урагана людям негде укрыться от дождя. Требуется древесина и сырой кирпич для укрепления стен.",
		"requirements": {
			"poor_brick": 4,
			"wood": 6
		},
		"reward_credits": 95,
		"dialogue_intro": "«Здравствуй! Семьи у холма замерзают без крыши. Если сделаешь пару партий кирпича и наберешь бревен — мы хорошо заплатим!»",
		"dialogue_complete": "«Спасибо тебе огромное! Теперь у людей будет сухой угол на ночь. Держи обещанную плату!»"
	},
	{
		"id": "contract_fuel_reserve",
		"title": "Топливо для ночных костров",
		"client": "Караван снабжения",
		"description": "Ночи становятся всё холоднее. Караванщикам срочно нужны плотные топливные брикеты для ночевок на привале.",
		"requirements": {
			"fuel_briquette": 6
		},
		"reward_credits": 110,
		"dialogue_intro": "«Ночами ветер пробирает до костей. Обычные сырые ветки чадят. Твои прессованные брикеты — то, что нужно!»",
		"dialogue_complete": "«Отличные брикеты, горят жарко и долго. Ты здорово выручил наш караван!»"
	},
	{
		"id": "contract_pure_water",
		"title": "Питьевая вода для разведки",
		"client": "Экспедиция геологов",
		"description": "Все открытые ручьи забиты илом после бури. Отряду необходима очищенная и бутилированная вода.",
		"requirements": {
			"clean_water": 3,
			"bottled_water": 1
		},
		"reward_credits": 140,
		"dialogue_intro": "«Разведчикам нельзя пить болотную жижу. Если наладил фильтры и розлив в стекло — заберем партию с премией!»",
		"dialogue_complete": "«Холодная, прозрачная вода! Ты спас экспедицию от жажды и болезней. Вот твои кредиты!»"
	},
	{
		"id": "contract_heavy_masonry",
		"title": "Капитальные стройматериалы",
		"client": "Инженерная служба округа",
		"description": "Восстановление моста через овраг требует закаленных огнеупорных кирпичей, стекла и чистого железа.",
		"requirements": {
			"fired_brick": 4,
			"glass": 2,
			"iron_ingot": 1
		},
		"reward_credits": 260,
		"dialogue_intro": "«Окружной мост снесло паводком. Для надежной переправы нужны прочные обожженные кирпичи и литой металл!»",
		"dialogue_complete": "«Невероятная работа! Настоящие закаленные материалы фабричного качества. Прими заслуженное вознаграждение!»"
	},
	{
		"id": "contract_fresh_harvest",
		"title": "Свежий урожай для поселка",
		"client": "Поселковая столовая",
		"description": "Люди истощены однообразным пайком. Требуются свежие овощи с восстановленной фермы: морковь и картофель.",
		"requirements": {
			"carrot": 4,
			"potato": 3
		},
		"reward_credits": 180,
		"dialogue_intro": "«Люди истосковались по свежей еде после бури! Если собрал первый урожай картошки и сладкой моркови — мы заберем всё по отличной цене!»",
		"dialogue_complete": "«Настоящие свежие овощи, только что из земли! Жители будут в восторге. Держи твои честно заработанные кредиты!»"
	},
	{
		"id": "contract_grain_supply",
		"title": "Продовольственный запас зерна",
		"client": "Караван снабжения",
		"description": "Каравану предстоит переход через бесплодную пустошь. Требуется партия пшеницы и свежеиспеченного хлеба.",
		"requirements": {
			"wheat": 6,
			"bread": 2
		},
		"reward_credits": 230,
		"dialogue_intro": "«Перед переходом через пустоши нам нужен надежный провиант: сытное зерно и ароматный печеный хлеб. Выручишь караван?»",
		"dialogue_complete": "«Превосходный хлеб и чистое зерно! Теперь караван выдержит любой дальний путь. Спасибо тебе, хозяин фермы!»"
	},
	{
		"id": "contract_electrification",
		"title": "Электрификация блокпоста",
		"client": "Караван снабжения",
		"description": "Обустройство безопасного ночного блокпоста на развилке дорог требует партии медных проводов и надежных аккумуляторных батарей.",
		"requirements": {
			"copper_wire": 4,
			"battery_cell": 2
		},
		"reward_credits": 320,
		"dialogue_intro": "«Ночью в пустошах небезопасно. Мы тянем линию освещения и ставим прожекторы на блокпосту. Нужны качественные провода и мощные аккумуляторы!»",
		"dialogue_complete": "«Отличные электрокомпоненты! Теперь на блокпосту будет светло как днем, и караваны смогут безопасно ночевать. Вот твоя щедрая награда!»"
	}
]

static var completed_contracts: Dictionary = {}

static func get_all_contracts() -> Array[Dictionary]:
	return CONTRACTS

static func get_contract(contract_id: String) -> Dictionary:
	for c in CONTRACTS:
		if c.id == contract_id:
			return c
	return {}

static func is_completed(contract_id: String) -> bool:
	return completed_contracts.get(contract_id, false)

static func can_fulfill(contract: Dictionary, inventory: Node) -> bool:
	if not inventory or contract.is_empty():
		return false
	if is_completed(contract.get("id", "")):
		return false
	
	var reqs: Dictionary = contract.get("requirements", {})
	for it_id in reqs.keys():
		var needed: int = reqs[it_id]
		var count: int = inventory.get_item_count(it_id) if inventory.has_method("get_item_count") else 0
		if count < needed:
			return false
	return true

static func fulfill_contract(contract_id: String, player: Node) -> bool:
	var contract: Dictionary = get_contract(contract_id)
	if contract.is_empty() or is_completed(contract_id):
		return false
	
	var inv = player.get("inventory") if "inventory" in player else null
	if not inv or not can_fulfill(contract, inv):
		return false
	
	# Списание требуемых товаров
	var reqs: Dictionary = contract.get("requirements", {})
	for it_id in reqs.keys():
		var needed: int = reqs[it_id]
		inv.remove_item(it_id, needed)
	
	# Начисление кредитов
	var reward: int = contract.get("reward_credits", 0)
	if reward > 0 and inv.has_method("add_credits"):
		inv.add_credits(reward)
	
	completed_contracts[contract_id] = true
	
	if player.has_method("notify"):
		var title: String = contract.get("title", "Заказ")
		player.notify("📜 Контракт «%s» выполнен! Получено +%d кредитов!" % [title, reward])
	
	return true

static func reset_completed() -> void:
	completed_contracts.clear()
