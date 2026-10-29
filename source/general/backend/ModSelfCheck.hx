package general.backend;

import sys.FileSystem;
import sys.io.File;

/**
 * 大肥鱼引擎 0.9.3 · 模组自检
 *
 * 起因：Locked Destiny 的 Functions.lua 里写了 set('ex.alpha', 0)，
 * 但 ex 这个精灵从来没被创建过 → setProperty 抛错 → 同一个 stepEvent 里
 * 后面几十行（背景恢复、特效还原）全部不执行 → 背景卡死。
 *
 * 这里在启动时静态扫一遍所有启用的模组：
 *   1. 收集每个模组里「创建过」的对象名（makeLuaSprite / makeAnimatedLuaSprite /
 *      makeColorBox / makeLuaText）
 *   2. 找出 set('名字.属性', ...) 里引用了但从没创建过的名字（幽灵对象）
 * 结果写进 logs/mod-selfcheck.txt，并在标题页提示数量。
 */
class ModSelfCheck
{
	// 引擎自带的、不需要模组创建的对象
	static var ENGINE_OBJECTS:Array<String> = [
		'boyfriend', 'dad', 'gf', 'camGame', 'camHUD', 'camOther', 'camZooming',
		'iconP1', 'iconP2', 'healthBar', 'healthBarBG', 'scoreTxt', 'timeBar', 'timeBarBG',
		'timeTxt', 'botplayTxt', 'health', 'score', 'misses', 'combo', 'ratingX', 'ratingY',
		'numScoreX', 'numScoreY', 'camFollow', 'camFollowPos', 'defaultCamZoom', 'camFollowLerp',
		'songLength', 'curStep', 'curBeat', 'curSection', 'inCutscene', 'paused',
		'playerStrums', 'opponentStrums', 'notes', 'unspawnNotes', 'strumLineNotes',
		'boyfriendGroup', 'dadGroup', 'gfGroup', 'camGameAngle', 'isPixelStage'
	];

	public static var lastReport:Array<String> = [];
	static var MAX_FILES:Int = 1500; // 扫描上限，防止标题页卡住

	public static function run():Array<String>
	{
		lastReport = [];
		#if MODS_ALLOWED
		try
		{
			var list = Mods.parseList();
			var out:Array<String> = [];
			for (modName in list.enabled)
			{
				var problems = checkMod(modName);
				for (p in problems) out.push(p);
			}
			lastReport = out;
			writeReport(out);
		}
		catch (e:Dynamic)
		{
			trace('[BF] selfcheck error: ' + e);
		}
		#end
		return lastReport;
	}

	static function collectLua(dir:String, acc:Array<String>):Void
	{
		if (!FileSystem.exists(dir) || !FileSystem.isDirectory(dir)) return;
		try
		{
			for (name in FileSystem.readDirectory(dir))
			{
				var p = dir + '/' + name;
				if (acc.length >= MAX_FILES) return;
				if (FileSystem.isDirectory(p)) collectLua(p, acc);
				else if (name.endsWith('.lua')) acc.push(p);
			}
		}
		catch (e:Dynamic) {}
	}

	static function checkMod(modName:String):Array<String>
	{
		var problems:Array<String> = [];
		var files:Array<String> = [];
		collectLua('mods/' + modName, files);
		if (files.length == 0) return problems;

		var created = new Map<String, Bool>();
		var used = new Map<String, Bool>();
		var where = new Map<String, String>();


		for (f in files)
		{
			var text:String = null;
			try text = File.getContent(f) catch (e:Dynamic) { continue; }
			if (text == null || text.length == 0) continue;

			var mkRe = ~/make(?:Animated)?LuaSprite\(\s*['"]([A-Za-z0-9_]+)['"]/g;
			var boxRe = ~/makeColorBox\(\s*['"]([A-Za-z0-9_]+)['"]/g;
			var txtRe = ~/makeLuaText\(\s*['"]([A-Za-z0-9_]+)['"]/g;
			var setRe = ~/set(?:Property)?\(\s*['"]([A-Za-z0-9_]+)\.[A-Za-z0-9_.]+['"]/g;
			for (re in [mkRe, boxRe, txtRe])
			{
				while (re.match(text)) created.set(re.matched(1), true);
			}
			while (setRe.match(text))
			{
				var n = setRe.matched(1);
				used.set(n, true);
				if (!where.exists(n)) where.set(n, f);
			}
		}

		for (n in used.keys())
		{
			if (created.exists(n)) continue;
			if (ENGINE_OBJECTS.indexOf(n) >= 0) continue;
			problems.push('[' + modName + '] 引用了从没创建过的对象 "' + n + '"  (' + where.get(n) + ')');
		}
		return problems;
	}

	static function writeReport(lines:Array<String>):Void
	{
		try
		{
			if (!FileSystem.exists('logs')) FileSystem.createDirectory('logs');
			var sb = new StringBuffer();
			sb.add('大肥鱼引擎 · 模组自检  ' + Date.now().toString() + '\n');
			sb.add('发现 ' + lines.length + ' 个可疑项\n\n');
			for (l in lines) sb.add(l + '\n');
			File.saveContent('logs/mod-selfcheck.txt', sb.toString());
			trace('[BF] 自检完成：' + lines.length + ' 项，已写入 logs/mod-selfcheck.txt');
		}
		catch (e:Dynamic) trace('[BF] selfcheck write error: ' + e);
	}
}
