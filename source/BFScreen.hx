package;

#if sys
import sys.io.File;
import sys.FileSystem;
#end

/**
 * [BF] 全屏模式开关
 *
 * 为什么不用 ClientPrefs：
 *   setupGame() 在 FlxGame 创建之前、在 Sys.setCwd() 之前就跑完了，
 *   那时候 ClientPrefs 还没加载、工作目录也还没切到数据目录。
 *   所以这里用绝对路径 + 独立小文件，完全不依赖引擎的时序。
 *
 * fill = false → 保持 16:9，左右留黑边（原行为）
 * fill = true  → 按屏幕比例铺满，边缘裁掉一点（不拉伸、不变形）
 */
class BFScreen
{
	public static var fill:Bool = false;

	static inline var DIR:String = '/storage/emulated/0/.BigFish Engine';
	static inline var FILE_NAME:String = 'bfscreen.conf';

	static function confPath():String
	{
		return DIR + '/' + FILE_NAME;
	}

	/** 启动时读一次（必须在 gameConfig.zoom 计算之前） */
	public static function load():Void
	{
		#if sys
		try
		{
			var p:String = confPath();
			if (FileSystem.exists(p))
			{
				var s:String = StringTools.trim(File.getContent(p));
				fill = (s == 'fill' || s == '1' || s == 'true');
			}
		}
		catch (e:Dynamic) { fill = false; }
		#end
	}

	/** 写回文件（设置页切换时调用） */
	public static function save():Void
	{
		#if sys
		try
		{
			if (!FileSystem.exists(DIR)) FileSystem.createDirectory(DIR);
			File.saveContent(confPath(), fill ? 'fill' : 'letterbox');
			return;
		}
		catch (e:Dynamic) {}
		#end
	}

	/** 切换并保存 */
	public static function toggle():Bool
	{
		fill = !fill;
		save();
		return fill;
	}
}
