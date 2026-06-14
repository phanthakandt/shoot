extends CanvasLayer
## Minimal level-up screen: a title + 3 buttons, one per card choice.
## Shown/hidden by GameManager. Works while Engine.time_scale == 0 because
## UI input (button presses) is not affected by time_scale.

@onready var card_buttons: Array[Button] = [
	$CardContainer/Card1,
	$CardContainer/Card2,
	$CardContainer/Card3,
]

var _current_cards: Array[Dictionary] = []


func _ready() -> void:
	visible = false
	GameManager.level_up_ui = self
	for i in range(card_buttons.size()):
		card_buttons[i].pressed.connect(_on_card_pressed.bind(i))


## Populates the 3 buttons with card name + description and shows the screen.
func show_cards(cards: Array[Dictionary]) -> void:
	_current_cards = cards
	for i in range(card_buttons.size()):
		if i < cards.size():
			var card: Dictionary = cards[i]
			card_buttons[i].text = "%s\n\n%s" % [card["name"], card["description"]]
			card_buttons[i].disabled = false
		else:
			card_buttons[i].text = ""
			card_buttons[i].disabled = true
	visible = true


func hide_cards() -> void:
	visible = false


func _on_card_pressed(index: int) -> void:
	if index < _current_cards.size():
		GameManager.select_card(_current_cards[index])
