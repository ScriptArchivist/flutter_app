package com.app.rtmp_stream

import android.app.Activity
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.hardware.camera2.CameraAccessException
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CameraMetadata
import android.media.MediaPlayer
import android.os.Build
import android.util.Log
import android.util.Size
import android.view.Surface
import android.view.SurfaceHolder
import android.view.View
import androidx.annotation.RequiresApi
import com.app.rtmp_stream.CameraPermissions.ResolutionPreset
import com.pedro.common.ConnectChecker
import com.pedro.encoder.input.gl.SpriteGestureController
import com.pedro.encoder.input.gl.render.filters.BaseFilterRender
import com.pedro.encoder.input.gl.render.filters.BasicDeformationFilterRender
import com.pedro.encoder.input.gl.render.filters.BeautyFilterRender
import com.pedro.encoder.input.gl.render.filters.BlackFilterRender
import com.pedro.encoder.input.gl.render.filters.BlurFilterRender
import com.pedro.encoder.input.gl.render.filters.BrightnessFilterRender
import com.pedro.encoder.input.gl.render.filters.CartoonFilterRender
import com.pedro.encoder.input.gl.render.filters.ChromaFilterRender
import com.pedro.encoder.input.gl.render.filters.ChromaticAberrationFilterRender
import com.pedro.encoder.input.gl.render.filters.CircleFilterRender
import com.pedro.encoder.input.gl.render.filters.ColorFilterRender
import com.pedro.encoder.input.gl.render.filters.ContrastFilterRender
import com.pedro.encoder.input.gl.render.filters.CropFilterRender
import com.pedro.encoder.input.gl.render.filters.DistortedTvFilterRender
import com.pedro.encoder.input.gl.render.filters.DuotoneFilterRender
import com.pedro.encoder.input.gl.render.filters.EarlyBirdFilterRender
import com.pedro.encoder.input.gl.render.filters.EdgeDetectionFilterRender
import com.pedro.encoder.input.gl.render.filters.ExposureFilterRender
import com.pedro.encoder.input.gl.render.filters.FireFilterRender
import com.pedro.encoder.input.gl.render.filters.GammaFilterRender
import com.pedro.encoder.input.gl.render.filters.GlitchFilterRender
import com.pedro.encoder.input.gl.render.filters.GreyScaleFilterRender
import com.pedro.encoder.input.gl.render.filters.HalftoneLinesFilterRender
import com.pedro.encoder.input.gl.render.filters.Image70sFilterRender
import com.pedro.encoder.input.gl.render.filters.LamoishFilterRender
import com.pedro.encoder.input.gl.render.filters.MoneyFilterRender
import com.pedro.encoder.input.gl.render.filters.NegativeFilterRender
import com.pedro.encoder.input.gl.render.filters.NoiseFilterRender
import com.pedro.encoder.input.gl.render.filters.PixelatedFilterRender
import com.pedro.encoder.input.gl.render.filters.PolygonizationFilterRender
import com.pedro.encoder.input.gl.render.filters.RGBSaturationFilterRender
import com.pedro.encoder.input.gl.render.filters.RainbowFilterRender
import com.pedro.encoder.input.gl.render.filters.RippleFilterRender
import com.pedro.encoder.input.gl.render.filters.RotationFilterRender
import com.pedro.encoder.input.gl.render.filters.SaturationFilterRender
import com.pedro.encoder.input.gl.render.filters.SepiaFilterRender
import com.pedro.encoder.input.gl.render.filters.SharpnessFilterRender
import com.pedro.encoder.input.gl.render.filters.SnowFilterRender
import com.pedro.encoder.input.gl.render.filters.TemperatureFilterRender
import com.pedro.encoder.input.gl.render.filters.ZebraFilterRender
import com.pedro.encoder.input.gl.render.filters.`object`.GifObjectFilterRender
import com.pedro.encoder.input.gl.render.filters.`object`.ImageObjectFilterRender
import com.pedro.encoder.input.gl.render.filters.`object`.SurfaceFilterRender
import com.pedro.encoder.input.gl.render.filters.`object`.TextObjectFilterRender
import com.pedro.encoder.input.video.CameraHelper.Facing.BACK
import com.pedro.encoder.input.video.CameraHelper.Facing.FRONT
import com.pedro.encoder.utils.gl.AspectRatioMode
import com.pedro.encoder.utils.gl.TranslateTo
import com.pedro.library.rtmp.RtmpCamera2
import com.pedro.library.util.BitrateAdapter
import com.pedro.library.view.OpenGlView
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import java.io.BufferedOutputStream
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.IOException
import java.io.OutputStream

class CameraNativeView(
    private var activity: Activity? = null,
    private var enableAudio: Boolean = false,
    private val preset: ResolutionPreset,
    private var cameraName: String,
    private var dartMessenger: DartMessenger? = null
) :
    PlatformView,
    SurfaceHolder.Callback,
    ConnectChecker {

    private val glView = OpenGlView(activity)
    private val rtmpCamera: RtmpCamera2
    private var isSurfaceCreated = false
    private var isSwitchingCamera = false
    private var fps = 0
    private val aBitrate = 128 * 1000
    private val vBitrate = 1200 * 1000
    private val bitrateAdapter: BitrateAdapter
    val spriteGestureController = SpriteGestureController()

    private var currentFilter: BaseFilterRender? = null
    private var currentFilterType: Int? = null

    init {
        glView.setAspectRatioMode(AspectRatioMode.Adjust)
        glView.holder.addCallback(this)
        rtmpCamera = RtmpCamera2(glView, this)
        rtmpCamera.streamClient.setReTries(10)
        rtmpCamera.setFpsListener { fps = it }
        bitrateAdapter = BitrateAdapter {
            rtmpCamera.setVideoBitrateOnFly(it)
        }.apply {
            setMaxBitrate(vBitrate + aBitrate)
        }
    }

    override fun surfaceCreated(holder: SurfaceHolder) {
        Log.d("CameraNativeView", "surfaceCreated")
        isSurfaceCreated = true

        if (isSwitchingCamera) {
            Log.d("CameraNativeView", "surfaceCreated ignored: switch in progress")
            return
        }

        if (!rtmpCamera.isOnPreview && !rtmpCamera.isStreaming) {
            startPreview(cameraName)
        }
    }

    override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
    }

    override fun surfaceDestroyed(holder: SurfaceHolder) {
        if (rtmpCamera.isOnPreview && !rtmpCamera.isStreaming) {
            rtmpCamera.stopPreview()
        }
        isSurfaceCreated = false
    }

    override fun onConnectionStarted(url: String) {
        activity?.runOnUiThread {
            dartMessenger?.send(DartMessenger.EventType.WAIT, "connection wait")
        }
    }

    override fun onConnectionSuccess() {
        activity?.runOnUiThread {
            dartMessenger?.send(DartMessenger.EventType.SUCCESS, "connection success")
        }
    }

    override fun onNewBitrate(bitrate: Long) {
        bitrateAdapter.adaptBitrate(bitrate, rtmpCamera.getStreamClient().hasCongestion())
    }

    @RequiresApi(Build.VERSION_CODES.LOLLIPOP)
    override fun onConnectionFailed(reason: String) {
        activity?.runOnUiThread {
            if (rtmpCamera.streamClient.reTry(5000, reason)) {
                dartMessenger?.send(DartMessenger.EventType.RTMP_RETRY, reason)
            } else {
                dartMessenger?.send(DartMessenger.EventType.RTMP_STOPPED, "Failed retry")
                rtmpCamera.stopStream()
            }
        }
    }

    override fun onDisconnect() {
        activity?.runOnUiThread {
            dartMessenger?.sendCameraClosingEvent()
        }
    }

    override fun onAuthError() {
        activity?.runOnUiThread {
            dartMessenger?.send(DartMessenger.EventType.ERROR, "Auth error")
        }
    }

    override fun onAuthSuccess() {
    }

    fun close() {
        Log.d("CameraNativeView", "close")
    }

    fun takePicture(filePath: String, result: MethodChannel.Result) {
        Log.d("CameraNativeView", "takePicture filePath: $filePath result: $result")
        val file = File(filePath)
        if (file.exists()) {
            result.error(
                "fileExists",
                "File at path '$filePath' already exists. Cannot overwrite.",
                null
            )
            return
        }
        glView.takePhoto {
            try {
                val outputStream: OutputStream = BufferedOutputStream(FileOutputStream(file))
                it.compress(Bitmap.CompressFormat.JPEG, 100, outputStream)
                outputStream.close()
                view.post { result.success(null) }
            } catch (e: IOException) {
                result.error("IOError", "Failed saving image", null)
            }
        }
    }

    fun startVideoRecording(filePath: String?, result: MethodChannel.Result) {
        if (filePath == null) {
            result.error("fileExists", "Must specify a filePath.", null)
            return
        }

        val file = File(filePath)
        if (file.exists()) {
            result.error(
                "fileExists",
                "File at path '$filePath' already exists. Cannot overwrite.",
                null
            )
            return
        }
        Log.d("CameraNativeView", "startVideoRecording filePath: $filePath result: $result")

        try {
            if (!rtmpCamera.isStreaming) {
                val streamingSize = CameraUtils.computeBestPreviewSize(activity, cameraName, preset)
                val size = streamingSize["size"] as Size
                val bitrateRes = streamingSize["bitrate"] as Int
                if ((enableAudio && rtmpCamera.prepareAudio()) && rtmpCamera.prepareVideo(
                        size.width,
                        size.height,
                        bitrateRes
                    )
                ) {
                    rtmpCamera.startRecord(filePath)
                }
            } else {
                rtmpCamera.startRecord(filePath)
            }
            result.success(null)
        } catch (e: CameraAccessException) {
            result.error("videoRecordingFailed", e.message, null)
        } catch (e: IOException) {
            result.error("videoRecordingFailed", e.message, null)
        }
    }

    fun startVideoStreaming(url: String?, bitrate: Int?, result: MethodChannel.Result) {
        Log.d("CameraNativeView", "startVideoStreaming url: $url")
        if (url == null) {
            result.error("startVideoStreaming", "Must specify a url.", null)
            return
        }

        try {
            if (!rtmpCamera.isStreaming) {
                val streamingSize = CameraUtils.computeBestPreviewSize(activity, cameraName, preset)
                val size = streamingSize["size"] as Size
                val bitrateRes = streamingSize["bitrate"] as Int
                if (rtmpCamera.isRecording || rtmpCamera.prepareAudio() && rtmpCamera.prepareVideo(
                        size.width,
                        size.height,
                        bitrate ?: bitrateRes
                    )
                ) {
                    rtmpCamera.startStream(url)
                } else {
                    result.error(
                        "videoStreamingFailed",
                        "Error preparing stream, This device cant do it",
                        null
                    )
                    return
                }
            } else {
                rtmpCamera.stopStream()
            }
            result.success(null)
        } catch (e: CameraAccessException) {
            result.error("videoStreamingFailed", e.message, null)
        } catch (e: IOException) {
            result.error("videoStreamingFailed", e.message, null)
        }
    }

    fun startVideoRecordingAndStreaming(
        filePath: String?,
        url: String?,
        bitrate: Int?,
        result: MethodChannel.Result
    ) {
        if (filePath == null) {
            result.error("fileExists", "Must specify a filePath.", null)
            return
        }
        if (File(filePath).exists()) {
            result.error("fileExists", "File at path '$filePath' already exists.", null)
            return
        }
        if (url == null) {
            result.error("fileExists", "Must specify a url.", null)
            return
        }
        try {
            startVideoRecording(filePath, result)
            startVideoStreaming(url, bitrate, result)
            result.success(null)
        } catch (e: CameraAccessException) {
            result.error("videoRecordingFailed", e.message, null)
        } catch (e: IOException) {
            result.error("videoRecordingFailed", e.message, null)
        }
    }

    @RequiresApi(Build.VERSION_CODES.LOLLIPOP)
    fun switchFlashLight(isEnable: Boolean?, result: MethodChannel.Result) {
        try {
            if (rtmpCamera.cameraFacing != BACK) {
                result.error("switchFlashLightFailed", "camera is Not BACK", null)
                return
            }
            if (isEnable == null) {
                result.error("switchFlashLightFailed", "isEnable not empty.", null)
                return
            }
            if (isEnable) {
                rtmpCamera.enableLantern()
            } else {
                rtmpCamera.disableLantern()
            }
            result.success(null)
        } catch (e: CameraAccessException) {
            result.error("switchFlashLightFailed", e.message, null)
        } catch (e: IOException) {
            result.error("switchFlashLightFailed", e.message, null)
        }
    }

    @RequiresApi(Build.VERSION_CODES.LOLLIPOP)
    fun switchCamera(cameraId: String?, result: MethodChannel.Result) {
        try {
            if (cameraId == null) {
                result.error("cameraIdExist", "empty cameraId!", null)
                return
            }

            if (cameraId == cameraName) {
                result.success(null)
                return
            }

            isSwitchingCamera = true
            cameraName = cameraId

            rtmpCamera.switchCamera(cameraId)

            glView.postDelayed({
                isSwitchingCamera = false
            }, 500)

            result.success(null)
        } catch (e: CameraAccessException) {
            isSwitchingCamera = false
            result.error("switchCameraFailed", e.message, null)
        } catch (e: IOException) {
            isSwitchingCamera = false
            result.error("switchCameraFailed", e.message, null)
        } catch (e: Exception) {
            isSwitchingCamera = false
            result.error("switchCameraFailed", e.message, null)
        }
    }

    @RequiresApi(Build.VERSION_CODES.LOLLIPOP)
    fun switchAudio(isEnable: Boolean?, result: MethodChannel.Result) {
        try {
            if (isEnable == null) {
                result.error("switchAudioFailed", "empty isEnable!", null)
                return
            }
            if (isEnable) {
                rtmpCamera.enableAudio()
            } else {
                rtmpCamera.disableAudio()
            }
            result.success(null)
        } catch (e: CameraAccessException) {
            result.error("switchAudioFailed", e.message, null)
        } catch (e: IOException) {
            result.error("switchAudioFailed", e.message, null)
        }
    }

    @RequiresApi(Build.VERSION_CODES.LOLLIPOP)
    fun setFilter(type: Int?, filePath: String?, result: MethodChannel.Result) {
        try {
            if (type == null) {
                result.error("setFilter", "type is empty", null)
                return
            }
            spriteGestureController.stopListener()
            when (type) {
                0 -> {
                    val f = BasicDeformationFilterRender()
                    rtmpCamera.glInterface?.setFilter(f)
                    currentFilter = f
                    currentFilterType = type
                    result.success(null)
                }
                1 -> {
                    val f = BeautyFilterRender()
                    rtmpCamera.glInterface?.setFilter(f)
                    currentFilter = f
                    currentFilterType = type
                    result.success(null)
                }
                2 -> {
                    val f = BlackFilterRender()
                    rtmpCamera.glInterface?.setFilter(f)
                    currentFilter = f
                    currentFilterType = type
                    result.success(null)
                }
                3 -> {
                    val f = BlurFilterRender()
                    rtmpCamera.glInterface?.setFilter(f)
                    currentFilter = f
                    currentFilterType = type
                    result.success(null)
                }
                4 -> {
                    val f = BrightnessFilterRender()
                    rtmpCamera.glInterface?.setFilter(f)
                    currentFilter = f
                    currentFilterType = type
                    result.success(null)
                }
                5 -> {
                    val f = CartoonFilterRender()
                    rtmpCamera.glInterface?.setFilter(f)
                    currentFilter = f
                    currentFilterType = type
                    result.success(null)
                }
                6 -> {
                    if (filePath == null) {
                        result.error("setFilter", "filePath Not Empty", null)
                        return
                    }
                    val chromaFilterRender = ChromaFilterRender()
                    rtmpCamera.glInterface?.setFilter(chromaFilterRender)
                    chromaFilterRender.setImage(BitmapFactory.decodeFile(filePath))
                    currentFilter = chromaFilterRender
                    currentFilterType = type
                    result.success(null)
                }
                else -> {
                    result.success(null)
                }
            }
        } catch (e: CameraAccessException) {
            result.error("setFilter", e.message, null)
        } catch (e: IOException) {
            result.error("setFilter", e.message, null)
        }
    }

    @RequiresApi(Build.VERSION_CODES.LOLLIPOP)
    fun removeFilter(type: Int?, result: MethodChannel.Result) {
        try {
            if (type == null) {
                result.error("removeFilter", "type is empty", null)
                return
            }
            spriteGestureController.stopListener()
            val filterToRemove = currentFilter
            val filterType = currentFilterType
            if (filterToRemove != null && filterType == type) {
                rtmpCamera.glInterface?.removeFilter(filterToRemove)
                currentFilter = null
                currentFilterType = null
            }
            result.success(null)
        } catch (e: CameraAccessException) {
            result.error("removeFilter", e.message, null)
        } catch (e: IOException) {
            result.error("removeFilter", e.message, null)
        }
    }

    fun stopVideoRecordingOrStreaming(result: MethodChannel.Result) {
        try {
            rtmpCamera.apply {
                if (isStreaming) stopStream()
                if (isRecording) stopRecord()
            }
            result.success(null)
        } catch (e: CameraAccessException) {
            result.error("videoRecordingFailed", e.message, null)
        } catch (e: IllegalStateException) {
            result.error("videoRecordingFailed", e.message, null)
        }
    }

    fun stopVideoRecording(result: MethodChannel.Result) {
        try {
            rtmpCamera.apply {
                if (isRecording) stopRecord()
            }
            result.success(null)
        } catch (e: CameraAccessException) {
            result.error("stopVideoRecordingFailed", e.message, null)
        } catch (e: IllegalStateException) {
            result.error("stopVideoRecordingFailed", e.message, null)
        }
    }

    fun stopVideoStreaming(result: MethodChannel.Result) {
        try {
            rtmpCamera.apply {
                if (isStreaming) stopStream()
            }
            result.success(null)
        } catch (e: CameraAccessException) {
            result.error("stopVideoStreamingFailed", e.message, null)
        } catch (e: IllegalStateException) {
            result.error("stopVideoStreamingFailed", e.message, null)
        }
    }

    fun pauseVideoRecording(result: MethodChannel.Result) {
        try {
            if (!rtmpCamera.isRecording) {
                result.error("pauseVideoRecording", "没有正在录制的视频", null)
                return
            }
            rtmpCamera.pauseRecord()
            result.success(null)
        } catch (e: CameraAccessException) {
            result.error("pauseVideoRecording", e.message, null)
        } catch (e: IllegalStateException) {
            result.error("pauseVideoRecording", e.message, null)
        }
    }

    fun resumeVideoRecording(result: MethodChannel.Result) {
        try {
            if (!rtmpCamera.isRecording) {
                result.error("resumeVideoRecording", "没有正在录制的视频", null)
                return
            }
            rtmpCamera.resumeRecord()
            result.success(null)
        } catch (e: CameraAccessException) {
            result.error("resumeVideoRecording", e.message, null)
        } catch (e: IllegalStateException) {
            result.error("resumeVideoRecording", e.message, null)
        }
    }

    fun startPreview(cameraNameArg: String? = null) {
        val targetCamera = if (cameraNameArg.isNullOrEmpty()) {
            cameraName
        } else {
            cameraNameArg
        }
        cameraName = targetCamera

        Log.d("CameraNativeView", "startPreview: $preset")
        if (isSurfaceCreated) {
            try {
                val previewSize = CameraUtils.computeBestPreviewSize(activity, cameraName, preset)
                val size = previewSize["size"] as Size
                rtmpCamera.startPreview(
                    if (isFrontFacing(targetCamera)) FRONT else BACK,
                    size.width,
                    size.height
                )
            } catch (e: CameraAccessException) {
                close()
                activity?.runOnUiThread {
                    dartMessenger?.send(DartMessenger.EventType.ERROR, "CameraAccessException")
                }
            } catch (e: Exception) {
                close()
                activity?.runOnUiThread {
                    dartMessenger?.send(
                        DartMessenger.EventType.ERROR,
                        e.message ?: "Camera error"
                    )
                }
            }
        }
    }

    fun getStreamStatistics(result: MethodChannel.Result) {
        val ret = hashMapOf<String, Any>()
        ret["cacheSize"] = rtmpCamera.streamClient.getCacheSize()
        ret["sentAudioFrames"] = rtmpCamera.streamClient.getSentAudioFrames()
        ret["sentVideoFrames"] = rtmpCamera.streamClient.getSentVideoFrames()
        ret["droppedAudioFrames"] = rtmpCamera.streamClient.getDroppedAudioFrames()
        ret["droppedVideoFrames"] = rtmpCamera.streamClient.getDroppedVideoFrames()
        ret["isAudioMuted"] = rtmpCamera.isAudioMuted
        ret["bitrate"] = rtmpCamera.bitrate
        ret["width"] = rtmpCamera.streamWidth
        ret["height"] = rtmpCamera.streamHeight
        ret["fps"] = fps
        result.success(ret)
    }

    override fun getView(): View {
        return glView
    }

    override fun dispose() {
        isSurfaceCreated = false
        isSwitchingCamera = false
    }

    private fun isFrontFacing(cameraName: String): Boolean {
        val currentActivity = activity ?: throw Exception("相机是空的")
        val cameraManager =
            currentActivity.getSystemService(Context.CAMERA_SERVICE) as? CameraManager
                ?: throw Exception("相机是空的")
        val characteristics = cameraManager.getCameraCharacteristics(cameraName)
        return characteristics.get(CameraCharacteristics.LENS_FACING) == CameraMetadata.LENS_FACING_FRONT
    }
}
