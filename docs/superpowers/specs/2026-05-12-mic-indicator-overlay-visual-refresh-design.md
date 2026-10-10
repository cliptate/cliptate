# MicIndicatorOverlay Visual Refresh Design

## Problem

`MicIndicatorOverlay` currently has the right structure and behavior, but its visual treatment has become inconsistent while iterating on glass, transparency, and contrast. The current look does not feel settled, and the frosted-glass direction is not the right fit for this component.

The main problems to solve are:

1. The overlay needs stronger separation from light or busy backgrounds.
2. The visual style should feel more like a compact macOS recording HUD than a decorative card.
3. The corners should remain fully transparent so the overlay feels lighter.
4. Text, timer, and icon content must stay legible across varying backgrounds.

## Chosen Direction

Use a **minimal macOS graphite HUD** style instead of Liquid Glass.

This keeps the component compact and system-like, while giving it enough visual weight to remain readable against bright desktop content. The result should feel closer to a transient recording status bar than a floating glass widget.

## Alternatives Considered

### 1. Graphite Slab (**chosen**)

A deep neutral graphite panel with subtle edge definition, transparent corners, restrained cool-blue waveform accents, and strong foreground contrast.

**Pros**
- Best separation from white or complex backgrounds
- Feels stable and intentional
- Solves the legibility problem directly

**Cons**
- Slightly less airy than a glass approach
- Reads more like a dedicated HUD than a pure system material surface

### 2. Neutral Float

A lighter semi-transparent floating panel with softer contrast and less boundary definition.

**Pros**
- Most similar to a generic macOS floating control
- Very restrained and visually quiet

**Cons**
- Still too weak against bright backgrounds
- Does not solve the core readability issue strongly enough

### 3. Outlined Panel

A semi-transparent panel that relies more heavily on border definition and less on body tone.

**Pros**
- Strong boundary clarity
- Cleaner than glass

**Cons**
- Feels more “designed” than system-native
- Border emphasis can become visually busier than desired

## Design Details

## 1. Overall Visual Language

The overlay should no longer use frosted glass as its primary identity. Instead, it should use a **dark graphite semi-transparent slab** with a restrained highlight and a very light edge stroke.

The visual character should be:

- compact
- neutral
- stable
- readable
- lightly elevated

It should not feel glossy, glowy, or decorative.

## 2. Panel Surface

The main panel remains the same size and shape family, but its color system changes:

- Base surface becomes a **dark neutral graphite**
- Transparency remains, but only enough to avoid feeling fully opaque
- The panel should visibly separate from the background even on white surfaces
- Any highlight treatment should be subtle and structural, not glassy

The main panel should use:

- one dark base layer
- one subtle top-to-bottom tone variation
- one restrained edge/border treatment

This is intended to make the overlay feel deliberate and calm instead of translucent and reactive.

## 3. Corners

The four outer corners should be **fully transparent**, not softly faded.

That means:

- no residual white, blur, or glow should remain in the corner cutout area
- the transparent cutout should affect the whole composed overlay surface, including highlight and border layers
- the cutout should visually lighten the silhouette without weakening the center panel

The corners are a shape treatment, not a lighting effect.

## 4. Foreground Elements

### Left icon

- No chip, badge, or container background
- If an app icon exists, show it directly with a small subtle shadow for contrast
- If no app icon exists, show a monochrome `mic.fill`

### Center waveform

- Keep the waveform centered and fixed in place
- Keep the 9-bar layout
- Use restrained cool-blue to grey-blue tones rather than bright neon blue
- The bars may have a very soft highlight or glow, but it should stay understated

### Right timer / activity

- No chip or badge background
- Timer text remains monospaced
- Spinner remains minimal
- Both use off-white foreground with a subtle dark shadow for readability

## 5. Transcript Area

If transcript content is visible:

- the transcript container should remain visually connected to the main panel
- it may be slightly darker than the panel body to provide a readable text bed
- it should not look like an independent floating card
- text should remain bright, but not pure white
- text should keep a subtle dark contrast shadow

The transcript area is a support surface, not a second primary panel.

## 6. Contrast Strategy

The design should solve conflict with bright backgrounds by combining:

- a darker panel body
- slightly reduced overall transparency versus the current version
- transparent corners only at the outer cutouts
- off-white foreground
- consistent low-radius dark text/icon shadow

This keeps the overlay readable without making it feel heavy or boxed.

## 7. What Will Not Change

This redesign is visual-only. The following stay unchanged:

- left / center / right layout
- centered waveform positioning
- transcript expansion behavior
- recording and processing states
- 9 waveform bars
- timer behavior
- current overlay dimensions unless a later follow-up explicitly changes them

## Implementation Notes

Implementation should simplify the current styling stack rather than layering on more effects.

Preferred structure:

1. A darker graphite panel base
2. A restrained highlight/edge pass
3. A full-overlay transparent corner cutout
4. Stronger foreground contrast handling

The implementation should remove or reduce any styling that reads as:

- Liquid Glass
- soft frosted material
- glossy highlights
- isolated mini chips for icon or timer

## Testing

Existing overlay tests should remain, but styling assertions should reflect the approved direction:

- fully transparent corners
- stronger panel/background separation
- retained foreground contrast protection
- unchanged waveform centering
- unchanged 9-bar waveform structure

## Success Criteria

The redesign is successful if:

1. On a white or light background, the overlay boundary is immediately readable.
2. Timer and transcript text remain easy to read at a glance.
3. The overlay feels like a compact macOS recording HUD, not a frosted card.
4. The corners feel cleanly cut out rather than softly faded.
5. The component still feels lightweight despite having stronger separation from the background.
