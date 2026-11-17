#!/usr/bin/env python3
"""Original CC0 packaging art. Rebuild with: python tools/gen_labels.py.
Two front panels wrap around each item; all text and brands are invented here.
"""
from pathlib import Path
import random
from PIL import Image, ImageDraw, ImageFont
OUT = Path(__file__).resolve().parents[1] / 'game/assets/textures'
LABELS = {
    'canned_food': ('TRAIL PANTRY', 'BAKED BEANS', '#9d382b'),
    'soda': ('MILEPOST', 'SPARKLING SODA', '#a92932'),
    'tinned_hotdogs': ('TRAIL PANTRY', 'HOTDOGS', '#ad572c'),
    'can_of_cashews': ('TRAIL PANTRY', 'ROASTED CASHEWS', '#8c6735'),
    'peaches_oreilly': ('TRAIL PANTRY', 'PEACHES', '#bc722b'),
    'mocha_cola': ('MILEPOST', 'MOCHA COLA', '#553926'),
    'digital_soda': ('MILEPOST', 'BLUE SODA', '#246893'),
    'matrix_cola': ('MILEPOST', 'COLA', '#315b37'),
    'crimson_chaos_energy': ('MILEPOST', 'ENERGY', '#892d34'),
    'feline_feast_cat_food': ('TRAIL PANTRY', 'CAT FOOD', '#735380'),
    'canine_chow_dog_food': ('TRAIL PANTRY', 'DOG FOOD', '#916238'),
    'water_clean': ('CLEAR TRAIL', 'DRINKING WATER', '#28637c'),
    'water_dirty': ('FIELD WATER', 'UNTREATED', '#625534'),
    'berry_juice': ('TRAIL ORCHARD', 'BERRY JUICE', '#773353'),
    'zap_power_juice': ('TRAIL ORCHARD', 'CITRUS JUICE', '#81732b'),
    'paint_can': ('ROADCOAT', 'ENAMEL PAINT', '#345b78'),
}
FONT = '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'
BOLD = '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'
def font(size, bold=False):
    return ImageFont.truetype(BOLD if bold else FONT, size)
for ident, (brand, name, color) in LABELS.items():
    im = Image.new('RGB', (1024, 512), '#e3d6b5')
    d = ImageDraw.Draw(im)
    rng = random.Random(ident)
    for _ in range(12000):
        x,y = rng.randrange(1024),rng.randrange(512)
        d.point((x,y),fill=rng.choice(['#d9cbaa','#e9ddbf','#cfc3a6']))
    d.rectangle((0,32,1024,480), outline=color, width=10)
    d.rectangle((0,110,1024,185),fill=color)
    for cx in [256,768]:
        d.text((cx,65),brand,font=font(30,True),fill=color,anchor='mm')
        size=32
        while d.textlength(name,font=font(size,True))>450: size-=1
        d.text((cx,148),name,font=font(size,True),fill='#fff4d8',anchor='mm')
        # Original mountain/road emblem.
        d.polygon([(cx-70,300),(cx,215),(cx+70,300)],fill=color)
        d.polygon([(cx-11,300),(cx+2,255),(cx+18,300)],fill='#e3d6b5')
        sub='BOIL BEFORE DRINKING' if ident=='water_dirty' else ('FOR METAL & WOOD' if ident=='paint_can' else 'PACKED FOR THE OPEN ROAD')
        d.text((cx,338),sub,font=font(18,True),fill=color,anchor='mm')
        d.text((cx,378),'KEEP SEALED | STORE COOL & DRY',font=font(14),fill=color,anchor='mm')
        for x in range(cx-50,cx+50,4):
            d.rectangle((x,405,x+rng.choice([1,2]),443),fill=color)
    im.save(OUT / f'label_{ident}.png')
# Fine embossed paper normal, deterministic and deliberately subtle.
rng=random.Random(17)
n=Image.new('RGB',(128,128)); n.putdata([(128+rng.randrange(-3,4),128+rng.randrange(-3,4),255) for _ in range(128*128)])
n.save(OUT/'label_paper_n.png')
print(f'Generated {len(LABELS)} original labels and paper normal')
