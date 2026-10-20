package com.naadchitra.naadchitra

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import java.nio.FloatBuffer

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.naadchitra/embedder"
    private var ortEnv: OrtEnvironment? = null
    private var session: OrtSession? = null
    private val initJob = Job()
    private val scope = CoroutineScope(Dispatchers.IO + initJob)

    // ImageNet normalization — must match tool/export_model.py exactly
    private val mean = floatArrayOf(0.485f, 0.456f, 0.406f)
    private val std = floatArrayOf(0.229f, 0.224f, 0.225f)
    private val IMG_SIZE = 224

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "initialize" -> initialize(result)
                "embed" -> {
                    val path = call.argument<String>("imagePath")
                    if (path.isNullOrEmpty()) {
                        result.error("INVALID_ARGS", "imagePath required", null)
                        return@setMethodCallHandler
                    }
                    scope.launch { embedImage(path, result) }
                }
                "release" -> {
                    releaseModel()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun initialize(result: MethodChannel.Result) {
        scope.launch {
            try {
                ortEnv = OrtEnvironment.getEnvironment()
                val modelBytes = assets.open("models/mobilenet_v3_small_fe.onnx").readBytes()
                session = ortEnv!!.createSession(modelBytes)
                val outputNames = session!!.outputNames
                Log.d("Naadchitra", "ONNX session ready, outputs: $outputNames")
                result.success(mapOf("success" to true, "outputs" to outputNames.toList()))
            } catch (e: Exception) {
                Log.e("Naadchitra", "Init failed", e)
                result.error("INIT_FAILED", e.message, e.stackTraceToString())
            }
        }
    }

    private fun embedImage(imagePath: String, result: MethodChannel.Result) {
        try {
            val env = ortEnv ?: return result.error("NOT_INIT", "Model not loaded", null)
            val sess = session ?: return result.error("NOT_INIT", "Model not loaded", null)

            // Decode with downsampling
            val opts = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(imagePath, opts)
            var sampleSize = 1
            while (opts.outWidth / sampleSize > 1024 || opts.outHeight / sampleSize > 1024) {
                sampleSize *= 2
            }
            opts.inJustDecodeBounds = false
            opts.inSampleSize = sampleSize
            val raw = BitmapFactory.decodeFile(imagePath, opts)
                ?: return result.error("INVALID_IMG", "Cannot decode", null)

            // Resize to 224x224
            val bitmap = Bitmap.createScaledBitmap(raw, IMG_SIZE, IMG_SIZE, true)
            if (raw !== bitmap) raw.recycle()

            // Pixel → NCHW float tensor with ImageNet normalization
            val pixels = IntArray(IMG_SIZE * IMG_SIZE)
            bitmap.getPixels(pixels, 0, IMG_SIZE, 0, 0, IMG_SIZE, IMG_SIZE)
            bitmap.recycle()

            val floatBuf = FloatBuffer.allocate(1 * 3 * IMG_SIZE * IMG_SIZE)
            for (y in 0 until IMG_SIZE) {
                for (x in 0 until IMG_SIZE) {
                    val p = pixels[y * IMG_SIZE + x]
                    val r = ((p shr 16 and 0xFF) / 255.0f - mean[0]) / std[0]
                    val g = ((p shr 8 and 0xFF) / 255.0f - mean[1]) / std[1]
                    val b = ((p and 0xFF) / 255.0f - mean[2]) / std[2]
                    // NCHW layout
                    val idx = y * IMG_SIZE + x
                    floatBuf.put(idx, r)           // channel 0
                    floatBuf.put(IMG_SIZE * IMG_SIZE + idx, g)  // channel 1
                    floatBuf.put(2 * IMG_SIZE * IMG_SIZE + idx, b)  // channel 2
                }
            }
            floatBuf.rewind()

            val shape = longArrayOf(1, 3, IMG_SIZE.toLong(), IMG_SIZE.toLong())
            val tensor = OnnxTensor.createTensor(env, floatBuf, shape)
            val inputName = sess.inputNames.first()
            val output = sess.run(mapOf(inputName to tensor))
            val embedding = (output[0].value as Array<FloatArray>)[0]
            tensor.close()

            // Convert to List for Flutter
            val embList = embedding.toList()
            result.success(mapOf("embedding" to embList))
        } catch (e: Exception) {
            Log.e("Naadchitra", "Embed failed", e)
            result.error("EMBED_FAILED", e.message, e.stackTraceToString())
        }
    }

    private fun releaseModel() {
        session?.close()
        session = null
        ortEnv?.close()
        ortEnv = null
    }

    override fun onDestroy() {
        initJob.cancel()
        releaseModel()
        super.onDestroy()
    }
}
