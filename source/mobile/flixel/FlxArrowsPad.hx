package mobile.flixel;

import flixel.FlxG;
import flixel.input.keyboard.FlxKey;
import mobile.flixel.input.FlxMobileInputManager;
import mobile.flixel.FlxButton;
import general.backend.Paths;
import general.backend.ClientPrefs;

/**
 * 底部一排 4 个方向箭头的触屏（模仿 FNF Global Slice 官方手机版的 Arrows 方案）。
 *
 * 用 NOTE_assets 音符贴图（0.9.2 补的资源），默认半透明静态箭头，
 * 按下播放 press 动画 + 变实，松开恢复。直接点箭头判定音符。
 */
class FlxArrowsPad extends FlxMobileInputManager
{
	// 4K 方向 → 静态帧名 / 按下帧名 / 键位
	static final ARROW_ANIMS:Array<String> = ['arrowLEFT', 'arrowDOWN', 'arrowUP', 'arrowRIGHT'];
	static final PRESS_ANIMS:Array<String> = ['purple press', 'blue press', 'green press', 'red press'];
	static final KEYS:Array<String> = ['note_left', 'note_down', 'note_up', 'note_right'];

	public var buttonLeft:FlxButton;
	public var buttonDown:FlxButton;
	public var buttonUp:FlxButton;
	public var buttonRight:FlxButton;

	public function new()
	{
		super();

		final hintWidth:Int = 150;
		final hintHeight:Int = 150;
		final noteSpacing:Int = 30;

		final xPos:Int = Math.floor((FlxG.width - (hintWidth + noteSpacing) * 4) / 2);
		final yPos:Int = Math.floor(FlxG.height - hintHeight - 50);

		buttonLeft = createArrowButton(xPos + 0 * (hintWidth + noteSpacing), yPos, 0, hintWidth, hintHeight);
		buttonDown = createArrowButton(xPos + 1 * (hintWidth + noteSpacing), yPos, 1, hintWidth, hintHeight);
		buttonUp   = createArrowButton(xPos + 2 * (hintWidth + noteSpacing), yPos, 2, hintWidth, hintHeight);
		buttonRight= createArrowButton(xPos + 3 * (hintWidth + noteSpacing), yPos, 3, hintWidth, hintHeight);

		add(buttonLeft);
		add(buttonDown);
		add(buttonUp);
		add(buttonRight);

		scrollFactor.set();
		updateTrackedButtons();
	}

	function createArrowButton(X:Float, Y:Float, index:Int, Width:Int, Height:Int):FlxButton
	{
		final ids:Array<FlxKey> = ClientPrefs.keyBinds.exists(KEYS[index]) ? ClientPrefs.keyBinds.get(KEYS[index]) : [];
		final btn = new FlxButton(X, Y, ids, null);

		btn.frames = Paths.getSparrowAtlas('NOTE_assets');
		btn.animation.addByPrefix('static', ARROW_ANIMS[index]);
		btn.animation.addByPrefix('pressed', PRESS_ANIMS[index], 24, false);
		btn.animation.play('static');
		btn.setGraphicSize(Width, Height);
		btn.updateHitbox();
		btn.scrollFactor.set();
		btn.antialiasing = ClientPrefs.data.antialiasing;
		btn.alpha = 0.6;

		btn.onDown.callback = function()
		{
			btn.animation.play('pressed', true);
			btn.alpha = 1;
		}
		btn.onUp.callback = function()
		{
			btn.animation.play('static', true);
			btn.alpha = 0.6;
		}
		btn.onOut.callback = function()
		{
			btn.animation.play('static', true);
			btn.alpha = 0.6;
		}

		return btn;
	}

	override function destroy():Void
	{
		super.destroy();
	}
}
