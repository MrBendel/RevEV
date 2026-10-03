package dev.revev.revev.auto

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.DashPathEffect
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RadialGradient
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import dev.revev.revev_engine.EngineBridge
import java.util.Locale
import kotlin.math.cos
import kotlin.math.sin

object CarInstrumentClusterRenderer {
    private const val NEEDLE_RED = 0xFFCF4936.toInt()
    private const val DIAL_IVORY_LIGHT = 0xFFF7F2E6.toInt()
    private const val DIAL_IVORY_MID = 0xFFDDD8CC.toInt()
    private const val DIAL_IVORY_DARK = 0xFFB4B0A6.toInt()
    private const val BEZEL_DARK = 0xFF141514.toInt()
    private const val DISPLAY_BG = 0xFF202321.toInt()
    private const val DISPLAY_AMBER = 0xFFD9B989.toInt()

    fun render(state: EngineBridge.State, width: Int = 600, height: Int = 360): Bitmap {
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)

        // 1. Draw Leather Background
        val bgPaint = Paint().apply {
            shader = LinearGradient(
                0f, 0f, width.toFloat(), height.toFloat(),
                intArrayOf(Color.rgb(0x27, 0x26, 0x24), Color.rgb(0x14, 0x14, 0x13), Color.rgb(0x1c, 0x1b, 0x1a)),
                null,
                Shader.TileMode.CLAMP
            )
        }
        canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), bgPaint)

        // Subtle stitch lines at top and bottom
        val stitchPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = 0x88A39880.toInt()
            style = Paint.Style.STROKE
            strokeWidth = 2f
            pathEffect = DashPathEffect(floatArrayOf(6f, 6f), 0f)
        }
        canvas.drawLine(10f, 16f, width - 10f, 16f, stitchPaint)
        canvas.drawLine(10f, height - 16f, width - 10f, height - 16f, stitchPaint)

        // 2. Left Gauge: Throttle
        val leftCenterX = width * 0.18f
        val leftCenterY = height * 0.54f
        val leftRadius = height * 0.28f
        drawAuxGauge(
            canvas = canvas,
            cx = leftCenterX,
            cy = leftCenterY,
            r = leftRadius,
            label = "THROTTLE",
            readout = "${(state.throttle * 100).toInt()}%",
            value = state.throttle.toDouble(),
            max = 1.0,
            divisions = 5
        )

        // 3. Right Gauge: Dual Speed (top) & Accel (bottom)
        val rightCenterX = width * 0.82f
        val rightCenterY = height * 0.54f
        val rightRadius = height * 0.28f
        drawDualSpeedAccelGauge(
            canvas = canvas,
            cx = rightCenterX,
            cy = rightCenterY,
            r = rightRadius,
            speedMph = state.speedMph,
            accelMps2 = state.accelMps2,
            running = state.playing
        )

        // 4. Center Gauge: RevEV Tachometer
        val mainCenterX = width * 0.50f
        val mainCenterY = height * 0.48f
        val mainRadius = height * 0.42f
        drawMainTachometer(
            canvas = canvas,
            cx = mainCenterX,
            cy = mainCenterY,
            r = mainRadius,
            rpm = state.rpm,
            maxRpm = 8000.0,
            gearDisplay = state.gearDisplay,
            running = state.playing
        )

        return bitmap
    }

    private fun drawBezel(canvas: Canvas, cx: Float, cy: Float, r: Float) {
        val bezelPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            shader = LinearGradient(
                cx - r, cy - r, cx + r, cy + r,
                intArrayOf(0xFF9E9B94.toInt(), 0xFF33332F.toInt(), 0xFF0A0A09.toInt(), 0xFF79766F.toInt()),
                null,
                Shader.TileMode.CLAMP
            )
        }
        canvas.drawCircle(cx, cy, r, bezelPaint)
        canvas.drawCircle(cx, cy, r * 0.96f, Paint(Paint.ANTI_ALIAS_FLAG).apply { color = BEZEL_DARK })
        canvas.drawCircle(cx, cy, r * 0.91f, Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0xFF5F605A.toInt() })

        val facePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            shader = RadialGradient(
                cx, cy - r * 0.2f, r * 0.9f,
                intArrayOf(DIAL_IVORY_LIGHT, DIAL_IVORY_MID, DIAL_IVORY_DARK),
                floatArrayOf(0f, 0.8f, 1f),
                Shader.TileMode.CLAMP
            )
        }
        canvas.drawCircle(cx, cy, r * 0.89f, facePaint)
    }

    private fun drawMainTachometer(
        canvas: Canvas,
        cx: Float,
        cy: Float,
        r: Float,
        rpm: Double,
        maxRpm: Double,
        gearDisplay: String,
        running: Boolean
    ) {
        drawBezel(canvas, cx, cy, r)

        val tickPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.rgb(0x24, 0x27, 0x26)
            strokeCap = Paint.Cap.BUTT
        }
        val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.rgb(0x20, 0x23, 0x22)
            textAlign = Paint.Align.CENTER
            textSize = r * 0.17f
            typeface = Typeface.DEFAULT_BOLD
        }

        val startAngle = Math.PI * 0.75
        val sweepAngle = Math.PI * 1.50
        val count = 8 * 4

        for (i in 0..count) {
            val a = startAngle + sweepAngle * (i.toDouble() / count)
            val major = (i % 4 == 0)
            val isRedline = (i.toDouble() / count) >= 0.75

            tickPaint.color = if (isRedline) NEEDLE_RED else Color.rgb(0x24, 0x27, 0x26)
            tickPaint.strokeWidth = r * (if (major) 0.022f else 0.010f)

            val p1X = cx + (cos(a) * r * 0.82f).toFloat()
            val p1Y = cy + (sin(a) * r * 0.82f).toFloat()
            val p2X = cx + (cos(a) * r * (if (major) 0.72f else 0.77f)).toFloat()
            val p2Y = cy + (sin(a) * r * (if (major) 0.72f else 0.77f)).toFloat()
            canvas.drawLine(p1X, p1Y, p2X, p2Y, tickPaint)

            if (major) {
                val num = (i / 4).toString()
                val tX = cx + (cos(a) * r * 0.60f).toFloat()
                val tY = cy + (sin(a) * r * 0.60f).toFloat() + (r * 0.06f)
                canvas.drawText(num, tX, tY, textPaint)
            }
        }

        // RevEV Brand Label
        val brandPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.rgb(0x24, 0x27, 0x26)
            textAlign = Paint.Align.CENTER
            textSize = r * 0.13f
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD_ITALIC)
        }
        canvas.drawText("RevEV", cx, cy - r * 0.28f, brandPaint)

        val unitPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = 0xFF51544D.toInt()
            textAlign = Paint.Align.CENTER
            textSize = r * 0.075f
            typeface = Typeface.DEFAULT
        }
        canvas.drawText("1/min × 1000", cx, cy - r * 0.14f, unitPaint)

        // Gear Badge
        if (running) {
            val badgeRect = RectF(cx - r * 0.22f, cy + r * 0.25f, cx + r * 0.22f, cy + r * 0.44f)
            canvas.drawRoundRect(badgeRect, r * 0.04f, r * 0.04f, Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0xFF161918.toInt() })
            val badgeStroke = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = 0xFF4A4539.toInt()
                style = Paint.Style.STROKE
                strokeWidth = 1.5f
            }
            canvas.drawRoundRect(badgeRect, r * 0.04f, r * 0.04f, badgeStroke)
            val badgeTextPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = NEEDLE_RED
                textAlign = Paint.Align.CENTER
                textSize = r * 0.13f
                typeface = Typeface.DEFAULT_BOLD
            }
            canvas.drawText(gearDisplay, cx, cy + r * 0.39f, badgeTextPaint)
        }

        // Digital RPM Display Box
        val dispRect = RectF(cx - r * 0.38f, cy + r * 0.50f, cx + r * 0.38f, cy + r * 0.72f)
        canvas.drawRoundRect(dispRect, r * 0.05f, r * 0.05f, Paint(Paint.ANTI_ALIAS_FLAG).apply { color = DISPLAY_BG })
        val dispTextPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = DISPLAY_AMBER
            textAlign = Paint.Align.CENTER
            textSize = r * 0.14f
            typeface = Typeface.DEFAULT_BOLD
        }
        val rpmText = if (running) "${rpm.toInt()}" else "READY"
        canvas.drawText(rpmText, cx, cy + r * 0.66f, dispTextPaint)

        // Needle
        val frac = (rpm / maxRpm).coerceIn(0.0, 1.0)
        val needleAngle = startAngle + sweepAngle * frac
        drawNeedle(canvas, cx, cy, r * 0.76f, needleAngle)

        // Center Cap
        canvas.drawCircle(cx, cy, r * 0.09f, Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0xFF131716.toInt() })
        canvas.drawCircle(cx - r * 0.015f, cy - r * 0.015f, r * 0.065f, Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0xFF303330.toInt() })
    }

    private fun drawAuxGauge(
        canvas: Canvas,
        cx: Float,
        cy: Float,
        r: Float,
        label: String,
        readout: String,
        value: Double,
        max: Double,
        divisions: Int
    ) {
        drawBezel(canvas, cx, cy, r)

        val startAngle = Math.PI * 0.75
        val sweepAngle = Math.PI * 1.50
        val count = divisions * 2

        val tickPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.rgb(0x24, 0x27, 0x26)
            strokeCap = Paint.Cap.BUTT
        }

        for (i in 0..count) {
            val a = startAngle + sweepAngle * (i.toDouble() / count)
            val major = (i % 2 == 0)
            tickPaint.strokeWidth = r * (if (major) 0.018f else 0.009f)

            val p1X = cx + (cos(a) * r * 0.83f).toFloat()
            val p1Y = cy + (sin(a) * r * 0.83f).toFloat()
            val p2X = cx + (cos(a) * r * (if (major) 0.73f else 0.78f)).toFloat()
            val p2Y = cy + (sin(a) * r * (if (major) 0.73f else 0.78f)).toFloat()
            canvas.drawLine(p1X, p1Y, p2X, p2Y, tickPaint)
        }

        val labelPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.rgb(0x24, 0x27, 0x26)
            textAlign = Paint.Align.CENTER
            textSize = r * 0.12f
            typeface = Typeface.DEFAULT_BOLD
        }
        canvas.drawText(label, cx, cy - r * 0.28f, labelPaint)

        // Readout display box
        val dispRect = RectF(cx - r * 0.40f, cy + r * 0.48f, cx + r * 0.40f, cy + r * 0.72f)
        canvas.drawRoundRect(dispRect, r * 0.06f, r * 0.06f, Paint(Paint.ANTI_ALIAS_FLAG).apply { color = DISPLAY_BG })
        val dispTextPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = DISPLAY_AMBER
            textAlign = Paint.Align.CENTER
            textSize = r * 0.15f
            typeface = Typeface.DEFAULT_BOLD
        }
        canvas.drawText(readout, cx, cy + r * 0.65f, dispTextPaint)

        val frac = (value / max).coerceIn(0.0, 1.0)
        val needleAngle = startAngle + sweepAngle * frac
        drawNeedle(canvas, cx, cy, r * 0.75f, needleAngle)

        canvas.drawCircle(cx, cy, r * 0.09f, Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0xFF131716.toInt() })
        canvas.drawCircle(cx - r * 0.015f, cy - r * 0.015f, r * 0.065f, Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0xFF303330.toInt() })
    }

    private fun drawDualSpeedAccelGauge(
        canvas: Canvas,
        cx: Float,
        cy: Float,
        r: Float,
        speedMph: Double,
        accelMps2: Double,
        running: Boolean
    ) {
        drawBezel(canvas, cx, cy, r)

        // Divider Line
        val divPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = 0xFF8A8579.toInt()
            strokeWidth = 1.5f
        }
        canvas.drawLine(cx - r * 0.65f, cy, cx + r * 0.65f, cy, divPaint)

        // Top Section: SPEED
        val labelPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.rgb(0x24, 0x27, 0x26)
            textAlign = Paint.Align.CENTER
            textSize = r * 0.11f
            typeface = Typeface.DEFAULT_BOLD
        }
        canvas.drawText("SPEED", cx, cy - r * 0.62f, labelPaint)

        val speedStart = Math.PI * 1.15
        val speedSweep = Math.PI * 0.70
        val tickPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.rgb(0x24, 0x27, 0x26)
            strokeCap = Paint.Cap.BUTT
        }

        for (i in 0..6) {
            val a = speedStart + speedSweep * (i.toDouble() / 6)
            tickPaint.strokeWidth = r * (if (i % 2 == 0) 0.018f else 0.010f)
            val p1X = cx + (cos(a) * r * 0.84f).toFloat()
            val p1Y = cy + (sin(a) * r * 0.84f).toFloat()
            val p2X = cx + (cos(a) * r * 0.74f).toFloat()
            val p2Y = cy + (sin(a) * r * 0.74f).toFloat()
            canvas.drawLine(p1X, p1Y, p2X, p2Y, tickPaint)
        }

        // Speed Display Box
        val speedBox = RectF(cx - r * 0.42f, cy - r * 0.36f, cx + r * 0.42f, cy - r * 0.14f)
        canvas.drawRoundRect(speedBox, r * 0.05f, r * 0.05f, Paint(Paint.ANTI_ALIAS_FLAG).apply { color = DISPLAY_BG })
        val speedTextPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = DISPLAY_AMBER
            textAlign = Paint.Align.CENTER
            textSize = r * 0.14f
            typeface = Typeface.DEFAULT_BOLD
        }
        val speedStr = if (running) "${speedMph.toInt()} MPH" else "0 MPH"
        canvas.drawText(speedStr, cx, cy - r * 0.20f, speedTextPaint)

        val speedFrac = (speedMph / 120.0).coerceIn(0.0, 1.0)
        val speedAngle = speedStart + speedSweep * speedFrac
        drawNeedle(canvas, cx, cy, r * 0.74f, speedAngle)

        // Bottom Section: ACCEL
        canvas.drawText("ACCEL", cx, cy + r * 0.18f, labelPaint)

        val accelSweep = Math.PI * 0.70
        val accelCenter = Math.PI * 0.50

        for (i in -2..2) {
            val frac = i / 2.0
            val a = accelCenter - frac * (accelSweep / 2)
            tickPaint.strokeWidth = r * (if (i == 0) 0.020f else 0.012f)
            val p1X = cx + (cos(a) * r * 0.84f).toFloat()
            val p1Y = cy + (sin(a) * r * 0.84f).toFloat()
            val p2X = cx + (cos(a) * r * 0.74f).toFloat()
            val p2Y = cy + (sin(a) * r * 0.74f).toFloat()
            canvas.drawLine(p1X, p1Y, p2X, p2Y, tickPaint)
        }

        // Accel Display Box
        val accelBox = RectF(cx - r * 0.45f, cy + r * 0.34f, cx + r * 0.45f, cy + r * 0.56f)
        canvas.drawRoundRect(accelBox, r * 0.05f, r * 0.05f, Paint(Paint.ANTI_ALIAS_FLAG).apply { color = DISPLAY_BG })
        val accelTextPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = DISPLAY_AMBER
            textAlign = Paint.Align.CENTER
            textSize = r * 0.13f
            typeface = Typeface.DEFAULT_BOLD
        }
        val prefix = if (accelMps2 >= 0) "+" else ""
        val accelStr = if (running) "$prefix${String.format(Locale.US, "%.1f", accelMps2)} m/s²" else "0.0 m/s²"
        canvas.drawText(accelStr, cx, cy + r * 0.50f, accelTextPaint)

        val accelFrac = (accelMps2 / 5.0).coerceIn(-1.0, 1.0)
        val accelAngle = accelCenter - accelFrac * (accelSweep / 2)
        drawNeedle(canvas, cx, cy, r * 0.74f, accelAngle)

        // Center Cap
        canvas.drawCircle(cx, cy, r * 0.09f, Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0xFF131716.toInt() })
        canvas.drawCircle(cx - r * 0.015f, cy - r * 0.015f, r * 0.065f, Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0xFF303330.toInt() })
    }

    private fun drawNeedle(canvas: Canvas, cx: Float, cy: Float, length: Float, angle: Double) {
        val needlePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = NEEDLE_RED
            style = Paint.Style.FILL
        }
        canvas.save()
        canvas.translate(cx, cy)
        canvas.rotate((angle * 180.0 / Math.PI).toFloat())

        val needlePath = Path().apply {
            moveTo(-length * 0.14f, -length * 0.024f)
            lineTo(length, -length * 0.007f)
            lineTo(length, length * 0.007f)
            lineTo(-length * 0.14f, length * 0.024f)
            close()
        }
        canvas.drawPath(needlePath, needlePaint)
        canvas.restore()
    }
}
