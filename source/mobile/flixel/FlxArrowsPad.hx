package mobile.flixel;

import flixel.FlxG;
import flixel.input.keyboard.FlxKey;
import flixel.tweens.FlxTween;
import flixel.tweens.FlxEase;
import mobile.flixel.input.FlxMobileInputManager;
import mobile.flixel.FlxButton;
import general.backend.Paths;
import general.backend.ClientPrefs;

/**
 * 底部一排 4 个箭头触屏 —— 复刻 FNF Global Slice 官方手机版的 Arrows 方案。
 *
 * 素材：assets/shared/images/mobileControls/{left,down,up,right}.png
 *       （浅灰箭头 + 黑描边，来自官方 0.8.6 包）
 * 手感：半透明常驻，按下变实并轻微放大，松开恢复。
 */
class FlxArrowsPad extends FlxMobileInputManager
{
	static final IMGS:Array<String> = ['mobileControls/left', 'mobileControls/down', 'mobileControls/up', 'mobileControls/right'];
	static final KEYS:Array<String> = ['note_left', 'note_down', 'note_up', 'note_right'];

	public var buttonLeft:FlxButton;
	public var buttonDown:FlxButton;
	public var buttonUp:FlxButton;
	public var buttonRight:FlxButton;

	// 版式（对齐官方：贴底、铺开、间距明显）
	static inline final BTN:Int = 118;
	static inline final GAP:Int = 46;
	static inline final MARGIN_BOTTOM:Int = 34;

	var tweens:Array<FlxTween> = [];

	public function new()
	{
		super();

		final step:Int = BTN + GAP;
		final totalW:Int = step * 4 - GAP;
		final x0:Int = Math.floor((FlxG.width - totalW) / 2);
		final y0:Int = Math.floor(FlxG.height - BTN - MARGIN_BOTTOM);

		buttonLeft = makeBtn(x0 + step * 0, y0, 0);
		buttonDown = makeBtn(x0 + step * 1, y0, 1);
		buttonUp = makeBtn(x0 + step * 2, y0, 2);
		buttonRight = makeBtn(x0 + step * 3, y0, 3);

		add(buttonLeft);
		add(buttonDown);
		add(buttonUp);
		add(buttonRight);

		scrollFactor.set();
		updateTrackedButtons();
	}

	function makeBtn(X:Float, Y:Float, index:Int):FlxButton
	{
		final ids:Array<FlxKey> = ClientPrefs.keyBinds.exists(KEYS[index]) ? ClientPrefs.keyBinds.get(KEYS[index]) : [];
		final btn = new FlxButton(X, Y, ids, null);

		btn.loadGraphic(Paths.image(IMGS[index]));
		btn.setGraphicSize(BTN, BTN);
		btn.updateHitbox();
		btn.solid = false;
		btn.immovable = true;
		btn.moves = false;
		btn.multiTouch = true;
		btn.scrollFactor.set();
		btn.antialiasing = ClientPrefs.data.antialiasing;
		btn.alpha = 0.55;

		btn.onDown.callback = function() press(btn);
		btn.onUp.callback = function() release(btn);
		btn.onOut.callback = function() release(btn);

		return btn;
	}

	function press(btn:FlxButton):Void
	{
		btn.alpha = 1;
		btn.scale.set(1.08, 1.08);
		btn.updateHitbox();
	}

	function release(btn:FlxButton):Void
	{
		btn.alpha = 0.55;
		btn.scale.set(1, 1);
		btn.updateHitbox();
	}

	override function destroy():Void
	{
		for (t in tweens) if (t != null) t.cancel();
		tweens = [];
		super.destroy();
	}
}
