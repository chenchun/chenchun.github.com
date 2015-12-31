---
layout: post
title: "ImageMagick"
description: ""
category: "图像处理"
tags: [ImageMagick, java]
---
{% include JB/setup %}

## ImageMagick

`ImageMagick`是一个免费的创建、编辑、合成图片的软件。它可以读取、转换、写入多种格式的图片。图片切割、颜色替换、各种效果的应用，图片的旋转、组合，文本，直线，多边形，椭圆，曲线，附加到图片伸展旋转。它可以支持以下程序语言： Perl, C, C++, Python, PHP, Ruby, Java

## 安装

由于依赖lib比较多，mac上最好使用`macPort`安装，port会自动将所有需要的依赖库安装上，先去 [macports官网下一个装上](http://www.macports.org/)

安装非常简单

	sudo port -v selfupdate
	sudo port install imagemagick


安装完测试一下
	
	identify -list font
	display -display :0
	
	#裁剪图像为64x64
	convert sourceimg.jpg -resize 64x64^ distimg.jpg
	
## 使用

各种功能参考官网例子 [http://www.imagemagick.org/Usage/](http://www.imagemagick.org/Usage/)


## Java客户端

官方推荐了一个 [JMagick](www.jmagick.org)，还有另一个 [IM4java](http://im4java.sourceforge.net/index.html) 

### JMagick

JMagick使用JNI调用ImageMagick C-API

优点：With JMagick, you have access to the low-level interface of IM and therefore you have a very detailed control of the processing of images. And you have better performance.

缺点：[JNI-hazard](http://im4java.sourceforge.net/docs/faq.html)

### IM4java

优点：the interface of the IM commandline is quite stable, so your java program (and the im4java-library) will work across many versions of IM. im4java also provides a better OO interface (the "language" of the IM-commandline with it's postfix-operation notation translates very easily into OO-notation). And most important: you can use im4java everywhere JMagick can't be used because of the JNI hazard (e.g. java application servers).
实际使用中IM4java非常稳定，大概10000/天

缺点：in contrast just generates the commandline for the ImageMagick commands and passes the generated line to the selected IM-command (using the java.lang.ProcessBuilder.start()-method). Your are limited to the capabilities of the IM commands.


## 图片基本信息

### java awt方式

	BufferedImage bi = ImageIO.read(is);

***使用中发现这种方式不支持JFIF格式图片***	

### Im4java方式

	Info imgInfo = new Info(file.getInputStream());
	imgInfo.getImageWidth()；

	/**
	 * 增加一个支持流读入的方法
	 *
     * @see org.im4java.core.Info
     *
     * @author chenchun
     * @version 1.0
     * @created 2012-11-14
     */
	public Info(InputStream is) throws InfoException, IOException {
        IMOperation op = new IMOperation();
        op.verbose();
        op.addImage("-");
        ByteArrayOutputStream bos = new ByteArrayOutputStream();
        Pipe pip = new Pipe(is, bos);
        try {
            IdentifyCmd identify = new IdentifyCmd();
            identify.setSearchPath(ImgUtil.COMMAND_PATH);
            identify.setInputProvider(pip);
            ArrayListOutputConsumer output = new ArrayListOutputConsumer();
            identify.setOutputConsumer(output);
            identify.run(op);
            ArrayList<String> cmdOutput = output.getOutput();

            StringBuilder lineAccu = new StringBuilder(80);
            for (String line : cmdOutput) {
                if (line.length() == 0) {
                    // accumulate empty line as part of current attribute
                    lineAccu.append("\n\n");
                } else if (line.indexOf(':') == -1) {
                    // interpret this as a continuation-line of the current
                    // attribute
                    lineAccu.append("\n").append(line);
                } else if (lineAccu.length() > 0) {
                    // new attribute, process old attribute first
                    parseLine(lineAccu.toString());
                    lineAccu = new StringBuilder(80);
                    lineAccu.append(line);
                } else {
                    // new attribute, but nothing old to process
                    lineAccu.append(line);
                }
            }
            // process last item
            if (lineAccu.length() > 0) {
                parseLine(lineAccu.toString());
            }

            // finish and add last hashtable to linked-list
            addBaseInfo();
            iAttribList.add(iAttributes);

        } catch (Exception ex) {
            throw new InfoException(ex);
        } finally {
            if (bos != null) {
                bos.close();
            }
            if (is != null) {
                is.close();
            }
        }
    }

***`ImageMagick` 比 `awt` 速度也快一些***


## 缩放图片


### java awt方式

	public static byte[] resizeByAwt(InputStream is, int width, int height) {
        try {
            BufferedImage bi = ImageIO.read(is);
            BufferedImage reducedImg = new BufferedImage(width, height, BufferedImage.TYPE_INT_RGB);
            reducedImg.getGraphics().drawImage(
                    bi.getScaledInstance(width, height, Image.SCALE_SMOOTH), 0, 0, null);
            ByteArrayOutputStream bos = new ByteArrayOutputStream();
            ImageIO.write(reducedImg, "jpg", bos);
            // ImageIO.write(reducedImg, "jpg", new
            // File("/Users/cc3514772b/a.jpg"));
            return bos.toByteArray();
        } catch (IOException e) {
            logger.error(e.getMessage(), e);
        }
        return null;
    }
    
    
### Im4java方式

	public static byte[] resize(InputStream is, int width, int height) {
        ConvertCmd cmd = new ConvertCmd();
        cmd.setSearchPath("/opt/local/bin");
        ByteArrayOutputStream bos = new ByteArrayOutputStream();
        Pipe pip = new Pipe(is, bos);
        cmd.setInputProvider(pip);
        cmd.setOutputConsumer(pip);
        IMOperation op = new IMOperation();
        op.addImage("-");
        op.resize(width, height, '^');
        op.addImage("jpg:-");
        try {
            cmd.run(op);
            return bos.toByteArray();
        } catch (Exception e) {
            logger.error(e.getMessage(), e);
        }
        return null;
    }
    
maven dependency

	<dependency>
		<groupId>org.im4java</groupId>
		<artifactId>im4java</artifactId>
		<version>1.2.0</version>
    </dependency>
