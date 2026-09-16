package com.yele.mobilefront

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Rect
import android.graphics.Typeface
import android.view.View

/**
 * Compteur de débit en surimpression par-dessus la barre d'état.
 *
 * Pourquoi un overlay : Android limite la taille des icônes de notification
 * au slot d'icônes de la barre d'état (~17 dp de rendu effectif), toujours
 * plus petit que le texte de l'horloge — aucune bitmap ne peut être plus
 * grande. Les applications speed-meter (Internet Speed Meter…) contournent
 * cela avec une fenêtre système TYPE_APPLICATION_OVERLAY dessinée dans la
 * barre d'état, à la taille exacte du texte de l'horloge.
 *
 * La fenêtre est NOT_TOUCHABLE + NOT_FOCUSABLE : elle ne gêne jamais les
 * interactions. La police est dimensionnée par mesure pour que la hauteur
 * réelle des chiffres remplisse toute la hauteur de la vue.
 */
@SuppressLint("ViewConstructor")
class SpeedOverlayView(context: Context) : View(context) {

    private var label = ""

    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE
        typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        // Fine ombre portée : lisible sur barre d'état claire ou sombre
        // (comme l'ombre de l'horloge système).
        setShadowLayer(4f, 0f, 1f, 0xCC000000.toInt())
    }

    init {
        // Le shadowLayer sur du texte exige le rendu software.
        setLayerType(LAYER_TYPE_SOFTWARE, null)
    }

    fun update(text: String) {
        if (text == label) return
        label = text
        contentDescription = text
        invalidate()
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        if (h <= 0) return
        // Taille de police CALCULÉE pour que la hauteur réelle des chiffres
        // (cap height, mesurée sur « 0 ») remplisse toute la hauteur de la
        // vue — même taille apparente que l'horloge « 09:31 ».
        paint.textSize = 100f
        val probe = Rect()
        paint.getTextBounds("0", 0, 1, probe)
        paint.textSize = 100f * h / probe.height().coerceAtLeast(1)
    }

    override fun onDraw(canvas: Canvas) {
        if (label.isEmpty()) return
        canvas.drawText(label, 0f, height - paint.descent(), paint)
    }
}
