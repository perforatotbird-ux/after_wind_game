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
			"poor_brick": 6,
			"wood": 8
		},
		"reward_credits": 100,
		"unlock_after": 0,
		"dialogue_intro": "«Здравствуй! Семьи у холма замерзают без крыши. Если сделаешь пару партий кирпича и наберешь бревен — мы хорошо заплатим!»",
		"dialogue_complete": "«Спасибо тебе огромное! Теперь у людей будет сухой угол на ночь. Держи обещанную плату!»"
	},
	{
		"id": "contract_fuel_reserve",
		"title": "Топливо для ночных костров",
		"client": "Караван снабжения",
		"description": "Ночи становятся всё холоднее. Караванщикам срочно нужны плотные топливные брикеты для ночевок на привале.",
		"requirements": {
			"fuel_briquette": 8
		},
		"reward_credits": 110,
		"unlock_after": 0,
		"dialogue_intro": "«Ночами ветер пробирает до костей. Обычные сырые ветки чадят. Твои прессованные брикеты — то, что нужно!»",
		"dialogue_complete": "«Отличные брикеты, горят жарко и долго. Ты здорово выручил наш караван!»"
	},
	{
		"id": "contract_pure_water",
		"title": "Питьевая вода для разведки",
		"client": "Экспедиция геологов",
		"description": "Все открытые ручьи забиты илом после бури. Отряду необходима очищенная и бутилированная вода.",
		"requirements": {
			"clean_water": 4,
			"bottled_water": 2
		},
		"reward_credits": 150,
		"unlock_after": 1,
		"dialogue_intro": "«Разведчикам нельзя пить болотную жижу. Если наладил фильтры и розлив в стекло — заберем партию с премией!»",
		"dialogue_complete": "«Холодная, прозрачная вода! Ты спас экспедицию от жажды и болезней. Вот твои кредиты!»"
	},
	{
		"id": "contract_heavy_masonry",
		"title": "Капитальные стройматериалы",
		"client": "Инженерная служба округа",
		"description": "Восстановление моста через овраг требует закаленных огнеупорных кирпичей, раствора для кладки, стекла и чистого железа.",
		"requirements": {
			"fired_brick": 6,
			"glass": 2,
			"mortar": 4,
			"iron_ingot": 1
		},
		"reward_credits": 280,
		"unlock_after": 3,
		"dialogue_intro": "«Окружной мост снесло паводком. Для надежной переправы нужны прочные обожженные кирпичи и литой металл!»",
		"dialogue_complete": "«Невероятная работа! Настоящие закаленные материалы фабричного качества. Прими заслуженное вознаграждение!»"
	},
	{
		"id": "contract_fresh_harvest",
		"title": "Свежий урожай для поселка",
		"client": "Поселковая столовая",
		"description": "Люди истощены однообразным пайком. Требуются свежие овощи с восстановленной фермы: морковь и картофель.",
		"requirements": {
			"carrot": 5,
			"potato": 4
		},
		"reward_credits": 180,
		"unlock_after": 0,
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
			"bread": 3
		},
		"reward_credits": 230,
		"unlock_after": 1,
		"dialogue_intro": "«Перед переходом через пустоши нам нужен надежный провиант: сытное зерно и ароматный печеный хлеб. Выручишь караван?»",
		"dialogue_complete": "«Превосходный хлеб и чистое зерно! Теперь караван выдержит любой дальний путь. Спасибо тебе, хозяин фермы!»"
	},
	{
		"id": "contract_electrification",
		"title": "Электрификация блокпоста",
		"client": "Караван снабжения",
		"description": "Обустройство безопасного ночного блокпоста на развилке дорог требует партии медных проводов, надежных аккумуляторных батарей и уличного фонаря.",
		"requirements": {
			"copper_wire": 4,
			"battery_cell": 2,
			"street_lamp_item": 1
		},
		"reward_credits": 320,
		"unlock_after": 3,
		"dialogue_intro": "«Ночью в пустошах небезопасно. Мы тянем линию освещения и ставим прожекторы на блокпосту. Нужны качественные провода и мощные аккумуляторы!»",
		"dialogue_complete": "«Отличные электрокомпоненты! Теперь на блокпосту будет светло как днем, и караваны смогут безопасно ночевать. Вот твоя щедрая награда!»"
	},
	{
		"id": "contract_master_tools",
		"title": "Оснащение экспедиции рудокопов",
		"client": "Гильдия старателей",
		"description": "Артель отправляется на дальние каменоломни. Требуется профессиональное снаряжение и оснастка: черенки, болты, ткань и литой металл.",
		"requirements": {
			"wooden_handle": 2,
			"bolt": 6,
			"fabric": 2,
			"iron_ingot": 3
		},
		"reward_credits": 450,
		"unlock_after": 3,
		"dialogue_intro": "«Мы снаряжаем поисковую партию на дальние скалы. Нужны надежные крепления, черенки, ткань и сталь для полевого инструмента. Заплатим звонкой монетой!»",
		"dialogue_complete": "«Первоклассные материалы и оснастка! С такими запасами наши старатели вскроют любую породу. Держи обещанные 450 кредитов!»"
	}
]

static var completed_contracts: Dictionary = {}

## Заказы по порядку открытия (сначала доступные, затем следующие волны).
static func get_all_contracts() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	var tiers: Array[int] = []
	for c in CONTRACTS:
		var t: int = int(c.get("unlock_after", 0))
		if not t in tiers:
			tiers.append(t)
	tiers.sort()
	for t in tiers:
		for c in CONTRACTS:
			if int(c.get("unlock_after", 0)) == t:
				list.append(c)
	return list

## Волны заказов: соседи узнают о базе по мере выполненных поставок.
## unlock_after — сколько заказов нужно сдать, чтобы этот появился на доске.
static func is_unlocked(contract: Dictionary) -> bool:
	return get_completed_count() >= int(contract.get("unlock_after", 0))

## Реплика Степана по прогрессу поставок (сюжет Главы 1).
const STORY_GREETINGS: Array[String] = [
	"Приветствую, выживший! Буря натворила бед. Первым делом — беженцам нужны стены, каравану топливо, а столовой свежие овощи. Справишься — о тебе узнает вся округа.",
	"Слух о твоей базе уже дошёл до геологов и каравана. У них заказы посерьёзнее: чистая вода в стекле и хлеб в дорогу.",
	"Ещё одна поставка — и с тобой захотят работать инженеры округа и старатели. Им нужны обожжённый кирпич, железо и электрика.",
	"Теперь ты — главный поставщик округи. Инженеры, блокпост и гильдия старателей ждут твоих партий!",
]

static func get_story_greeting() -> String:
	return STORY_GREETINGS[mini(get_completed_count(), STORY_GREETINGS.size() - 1)]

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
	if is_completed(contract.get("id", "")) or not is_unlocked(contract):
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
	
	var unlocked_before: int = _count_unlocked()
	completed_contracts[contract_id] = true
	var newly_unlocked: int = _count_unlocked() - unlocked_before
	
	const AudioManager = preload("res://scripts/audio/audio_manager.gd")
	AudioManager.play("coins")
	
	if player.has_method("notify"):
		var title: String = contract.get("title", "Заказ")
		player.notify("📜 Контракт «%s» выполнен! Получено +%d кредитов!" % [title, reward])
		if newly_unlocked > 0:
			player.notify("📬 На доске новые заказы: %d. Загляните к Степану!" % newly_unlocked)
	
	return true

static func reset_completed() -> void:
	completed_contracts.clear()

static func get_completed_count() -> int:
	return completed_contracts.size()

static func _count_unlocked() -> int:
	var n: int = 0
	for c in CONTRACTS:
		if is_unlocked(c):
			n += 1
	return n
