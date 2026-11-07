extends Node2D

# نمونه قابل‌بازی: فوتبال دوبعدی از نمای بالا
# کنترل موبایل: جوی‌استیک مجازی در نیمه چپ، پاس و شوت در سمت راست
# کنترل رایانه: WASD/جهت‌ها، Space برای پاس، Enter برای شوت

const FIELD := Rect2(42, 42, 876, 456)
const TEAM_BLUE := Color("#58a6ff")
const TEAM_RED := Color("#ff6577")
const WHITE := Color("#f4f7f4")
const GOLD := Color("#ffd166")
const GREEN := Color("#19734d")

var blue := []
var red := []
var ball := Vector2(480, 270)
var ball_velocity := Vector2.ZERO
var controlled := 0
var joystick_id := -1
var joystick_origin := Vector2(145, 420)
var joystick_pos := Vector2(145, 420)
var move_vector := Vector2.ZERO
var pass_flash := 0.0
var message := "با جوی‌استیک حرکت کن؛ پاس و شوت بزن"
var score_blue := 0
var score_red := 0
var match_time := 90.0
var finished := false
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	rng.randomize()
	_make_teams()
	set_process(true)
	set_process_input(true)

func _make_teams() -> void:
	blue.clear()
	red.clear()
	var left_positions = [
		Vector2(160,270), Vector2(285,130), Vector2(285,220),
		Vector2(285,320), Vector2(285,410), Vector2(410,170),
		Vector2(410,270), Vector2(410,370), Vector2(565,150),
		Vector2(565,270), Vector2(565,390)
	]
	var right_positions = [
		Vector2(800,270), Vector2(675,130), Vector2(675,220),
		Vector2(675,320), Vector2(675,410), Vector2(550,170),
		Vector2(550,270), Vector2(550,370), Vector2(395,150),
		Vector2(395,270), Vector2(395,390)
	]
	for i in range(11):
		blue.append({"p": left_positions[i], "home": left_positions[i], "stamina": 100.0})
		red.append({"p": right_positions[i], "home": right_positions[i], "stamina": 100.0})

func _process(delta: float) -> void:
	if finished:
		queue_redraw()
		return
	match_time = maxf(0.0, match_time - delta)
	if match_time <= 0.0:
		finished = true
		message = "پایان مسابقه"
	_update_user(delta)
	_update_opponents(delta)
	_update_ball(delta)
	_update_goal_checks()
	pass_flash = maxf(0.0, pass_flash - delta)
	queue_redraw()

func _update_user(delta: float) -> void:
	var keys := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): keys.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): keys.x += 1
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): keys.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): keys.y += 1
	var direction := move_vector if move_vector.length() > 0.08 else keys.normalized()
	var player: Dictionary = blue[controlled]
	if direction.length() > 0.05:
		player.p += direction.normalized() * 205.0 * delta
		player.p = _clamp_field(player.p)
		player.stamina = maxf(20.0, player.stamina - 2.0 * delta)
	blue[controlled] = player
	# بازیکنان بدون توپ به شکل ساده فضای خالی را پوشش می‌دهند.
	for i in range(11):
		if i == controlled: continue
		var p: Dictionary = blue[i]
		var target: Vector2 = p.home
		if ball.x < 470: target += Vector2(-15, 0)
		p.p = p.p.move_toward(target, 38.0 * delta)
		blue[i] = p

func _update_opponents(delta: float) -> void:
	var nearest := 0
	var nearest_dist := INF
	for i in range(11):
		var d: float = red[i].p.distance_to(ball)
		if d < nearest_dist:
			nearest_dist = d
			nearest = i
	for i in range(11):
		var p: Dictionary = red[i]
		var target: Vector2 = p.home
		if i == nearest:
			target = ball + Vector2(-18, 0)
		else:
			target += (ball - Vector2(480,270)) * 0.10
		p.p = p.p.move_toward(target, (105.0 if i == nearest else 34.0) * delta)
		red[i] = p
	if nearest_dist < 24.0 and ball.x > 500 and rng.randf() < 0.012:
		ball_velocity = Vector2(-260, rng.randf_range(-95,95))
		message = "حریف توپ را شوت کرد!"

func _update_ball(delta: float) -> void:
	var holder := _blue_with_ball()
	if holder >= 0:
		var p: Vector2 = blue[holder].p
		var desired := p + Vector2(18, 7)
		ball = ball.move_toward(desired, 520.0 * delta)
	else:
		var opponent := _red_with_ball()
		if opponent >= 0:
			ball = ball.move_toward(red[opponent].p + Vector2(-18, 5), 420.0 * delta)
		else:
			ball += ball_velocity * delta
			ball_velocity = ball_velocity.move_toward(Vector2.ZERO, 175.0 * delta)
			ball.y = clampf(ball.y, FIELD.position.y + 8, FIELD.end.y - 8)
			if ball.x < FIELD.position.x + 8 or ball.x > FIELD.end.x - 8:
				ball_velocity.x *= -0.55
			if ball.y <= FIELD.position.y + 8 or ball.y >= FIELD.end.y - 8:
				ball_velocity.y *= -0.55
	# تصاحب توپ در فاصله نزدیک
	if _blue_with_ball() < 0 and _red_with_ball() < 0 and ball_velocity.length() < 120:
		var bidx := _nearest_player(blue, ball)
		var ridx := _nearest_player(red, ball)
		if blue[bidx].p.distance_to(ball) < 19 and blue[bidx].p.distance_to(ball) < red[ridx].p.distance_to(ball):
			controlled = bidx
			message = "توپ در اختیار تیم توست"
		elif red[ridx].p.distance_to(ball) < 18:
			message = "حریف صاحب توپ شد"

func _blue_with_ball() -> int:
	if blue[controlled].p.distance_to(ball) < 27 and ball_velocity.length() < 55:
		return controlled
	return -1

func _red_with_ball() -> int:
	var idx := _nearest_player(red, ball)
	if red[idx].p.distance_to(ball) < 23 and ball_velocity.length() < 55:
		return idx
	return -1

func _nearest_player(team: Array, point: Vector2) -> int:
	var idx := 0
	var best := INF
	for i in range(team.size()):
		var d: float = team[i].p.distance_to(point)
		if d < best:
			best = d
			idx = i
	return idx

func _clamp_field(p: Vector2) -> Vector2:
	return Vector2(clampf(p.x, FIELD.position.x + 18, FIELD.end.x - 18),
		clampf(p.y, FIELD.position.y + 18, FIELD.end.y - 18))

func _update_goal_checks() -> void:
	if ball.x < FIELD.position.x + 2 and ball.y > 220 and ball.y < 320:
		score_red += 1
		_reset_after_goal("حریف گل زد!")
	elif ball.x > FIELD.end.x - 2 and ball.y > 220 and ball.y < 320:
		score_blue += 1
		_reset_after_goal("گل! عالی بود!")

func _reset_after_goal(text: String) -> void:
	message = text
	ball = Vector2(480,270)
	ball_velocity = Vector2.ZERO
	for i in range(11):
		blue[i].p = blue[i].home
		red[i].p = red[i].home
	controlled = 0

func _pass_ball() -> void:
	var current: Vector2 = blue[controlled].p
	var best_idx := -1
	var best_score := -INF
	for i in range(11):
		if i == controlled: continue
		var teammate: Vector2 = blue[i].p
		var forward := teammate.x - current.x
		var distance := teammate.distance_to(current)
		var score := forward * 0.8 - distance * 0.22
		if forward > -30 and score > best_score:
			best_score = score
			best_idx = i
	if best_idx >= 0:
		var target: Vector2 = blue[best_idx].p
		ball = current
		ball_velocity = (target - current).normalized() * 440.0
		controlled = best_idx
		message = "پاس به بازیکن هم‌تیمی"
		pass_flash = 0.25

func _shoot_ball() -> void:
	var p: Vector2 = blue[controlled].p
	ball = p
	var target := Vector2(940, 270 + rng.randf_range(-70,70))
	ball_velocity = (target - p).normalized() * 650.0
	message = "شوت به سمت دروازه!"
	pass_flash = 0.3

func _switch_player() -> void:
	var best := _nearest_player(blue, ball)
	controlled = best
	message = "بازیکن انتخاب‌شده تغییر کرد"

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			var pos: Vector2 = event.position
			if pos.x < get_viewport_rect().size.x * 0.48 and pos.y > 260:
				joystick_id = event.index
				joystick_origin = pos
				joystick_pos = pos
			elif pos.x > get_viewport_rect().size.x * 0.70:
				if pos.y > get_viewport_rect().size.y * 0.67:
					_shoot_ball()
				elif pos.y > get_viewport_rect().size.y * 0.40:
					_pass_ball()
				else:
					_switch_player()
		elif event.index == joystick_id:
			joystick_id = -1
			move_vector = Vector2.ZERO
	elif event is InputEventScreenDrag and event.index == joystick_id:
		joystick_pos = event.position
		move_vector = (joystick_pos - joystick_origin).limit_length(58) / 58.0
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE: _pass_ball()
			KEY_ENTER, KEY_KP_ENTER: _shoot_ball()
			KEY_TAB: _switch_player()
			KEY_ESCAPE:
				finished = not finished
				message = "بازی متوقف شد" if finished else "بازی ادامه دارد"

func _draw() -> void:
	_draw_field()
	_draw_players(red, TEAM_RED, false)
	_draw_players(blue, TEAM_BLUE, true)
	_draw_ball()
	_draw_hud()
	_draw_controls()

func _draw_field() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(960,540)), Color("#07111b"))
	draw_rect(FIELD, GREEN)
	for i in range(10):
		var x := FIELD.position.x + i * FIELD.size.x / 10.0
		if i % 2 == 0:
			draw_rect(Rect2(x, FIELD.position.y, FIELD.size.x/10.0, FIELD.size.y), Color(1,1,1,0.035))
	draw_rect(FIELD, WHITE, false, 3)
	draw_line(Vector2(480,42), Vector2(480,498), WHITE, 2)
	draw_arc(Vector2(480,270), 65, 0, TAU, 64, WHITE, 2)
	draw_circle(Vector2(480,270), 4, WHITE)
	draw_rect(Rect2(42,180,105,180), WHITE, false, 2)
	draw_rect(Rect2(42,220,42,100), WHITE, false, 2)
	draw_rect(Rect2(813,180,105,180), WHITE, false, 2)
	draw_rect(Rect2(876,220,42,100), WHITE, false, 2)
	draw_rect(Rect2(20,220,22,100), Color("#dce6e2"))
	draw_rect(Rect2(918,220,22,100), Color("#dce6e2"))

func _draw_players(team: Array, color: Color, user_team: bool) -> void:
	for i in range(team.size()):
		var p: Vector2 = team[i].p
		var selected := user_team and i == controlled
		if selected:
			draw_arc(p, 24, 0, TAU, 36, GOLD, 3)
			draw_circle(p + Vector2(0,-29), 4, GOLD)
		draw_circle(p + Vector2(2,4), 13, Color(0,0,0,0.28))
		draw_circle(p, 12, color)
		draw_arc(p, 12, 0, TAU, 24, Color.WHITE, 1.5)
		draw_string(ThemeDB.fallback_font, p + Vector2(-4,4), str(i+1), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.WHITE)

func _draw_ball() -> void:
	draw_circle(ball + Vector2(2,3), 8, Color(0,0,0,0.35))
	draw_circle(ball, 7, Color.WHITE)
	draw_arc(ball, 7, 0, TAU, 20, Color("#20242b"), 1)
	draw_line(ball+Vector2(-4,-2),ball+Vector2(3,3),Color("#20242b"),1.5)

func _draw_hud() -> void:
	draw_rect(Rect2(300,7,360,28), Color(0,0,0,0.58), true, 8)
	draw_string(ThemeDB.fallback_font, Vector2(420,27), "%d   -   %d" % [score_blue,score_red], HORIZONTAL_ALIGNMENT_CENTER, 120, 20, WHITE)
	draw_string(ThemeDB.fallback_font, Vector2(55,25), "BLUE  •  %02d:%02d" % [int(match_time)/60,int(match_time)%60], HORIZONTAL_ALIGNMENT_LEFT, 180, 14, WHITE)
	draw_string(ThemeDB.fallback_font, Vector2(750,25), "RED  •  DEMO", HORIZONTAL_ALIGNMENT_LEFT, 150, 14, Color("#ffb4bc"))
	draw_rect(Rect2(260,505,440,27), Color(0,0,0,0.62), true, 7)
	draw_string(ThemeDB.fallback_font, Vector2(280,524), message, HORIZONTAL_ALIGNMENT_CENTER, 400, 13, WHITE)
	if finished:
		draw_rect(Rect2(270,190,420,150), Color(0,0,0,0.82), true, 16)
		draw_string(ThemeDB.fallback_font, Vector2(380,250), "FULL TIME", HORIZONTAL_ALIGNMENT_LEFT, 220, 30, GOLD)
		draw_string(ThemeDB.fallback_font, Vector2(385,292), "Tap screen to restart", HORIZONTAL_ALIGNMENT_LEFT, 220, 15, WHITE)

func _draw_controls() -> void:
	# جوی‌استیک مجازی
	var origin := joystick_origin if joystick_id != -1 else Vector2(145,420)
	draw_circle(origin, 58, Color(0.02,0.04,0.08,0.42))
	draw_arc(origin, 58, 0, TAU, 48, Color(1,1,1,0.42), 2)
	var knob := joystick_pos if joystick_id != -1 else origin
	draw_circle(knob, 24, Color(0.85,0.9,1,0.42))
	# دکمه‌ها
	_draw_button(Vector2(835,445), 43, "شوت", Color("#df8b4c"))
	_draw_button(Vector2(755,365), 38, "پاس", Color("#4f9ed8"))
	_draw_button(Vector2(850,330), 31, "تعویض", Color("#8c78c9"))

func _draw_button(pos: Vector2, radius: float, label: String, color: Color) -> void:
	draw_circle(pos, radius, Color(color.r,color.g,color.b,0.82))
	draw_arc(pos, radius, 0, TAU, 40, Color.WHITE, 2)
	draw_string(ThemeDB.fallback_font, pos+Vector2(-radius+5,5), label, HORIZONTAL_ALIGNMENT_CENTER, radius*2-10, 13, Color.WHITE)
