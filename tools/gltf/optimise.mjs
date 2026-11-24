// Slim a rigged character GLB for mobile. usage: npm install && node optimise.mjs in.glb out.glb
import { NodeIO } from '@gltf-transform/core';
import { ALL_EXTENSIONS } from '@gltf-transform/extensions';
import { prune, dedup, textureCompress, getBounds } from '@gltf-transform/functions';
import sharp from 'sharp';
const [,, inPath, outPath] = process.argv;
const io = new NodeIO().registerExtensions(ALL_EXTENSIONS);
const doc = await io.read(inPath);
const root = doc.getRoot();
console.log('animations:', root.listAnimations().map(a => `${a.getName()} (${a.listChannels().length} ch)`));
for (const a of root.listAnimations()) a.dispose();   // we animate in code
for (const m of root.listMeshes()) for (const prim of m.listPrimitives()) {
  if (prim.getAttribute('TANGENT') && !prim.getMaterial()?.getNormalTexture()) prim.setAttribute('TANGENT', null);  // no normal map: tangents unused
}
console.log('materials:', root.listMaterials().map(m => m.getName()));
for (const t of root.listTextures()) console.log('texture', t.getName(), t.getMimeType(), t.getSize(), t.getImage().byteLength);
await doc.transform(
  dedup(),
  prune(),
  textureCompress({ encoder: sharp, targetFormat: 'jpeg', resize: [1024, 1024], quality: 82 }),
);
for (const t of root.listTextures()) console.log('-> texture', t.getMimeType(), t.getSize(), t.getImage().byteLength);
const scene = root.listScenes()[0];
const b = getBounds(scene);
console.log('bounds min', b.min.map(v => v.toFixed(3)), 'max', b.max.map(v => v.toFixed(3)));
for (const n of root.listNodes()) if (n.getSkin() || n.getMesh()) console.log('node', n.getName(), 'T', n.getTranslation(), 'R', n.getRotation(), 'S', n.getScale());
await io.write(outPath, doc);
