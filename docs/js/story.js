/**
 * story.js — scene order and diagram captions.
 *
 * The prose itself lives in index.html, so the whole story is readable with
 * JavaScript switched off. This file holds only what the *diagram* needs: the
 * order of the scenes, their ids, and the few words drawn inside the SVG.
 *
 * To add, remove or reorder a scene:
 *   1. edit this array;
 *   2. add or move the matching <article class="step" data-scene="<id>"> in
 *      index.html;
 *   3. add a layout with the same id in scene-graph.js.
 * main.js logs a warning if the DOM and this array disagree.
 */

export const SCENES = [
  {
    id: 'questions',
    label: 'Questions',
    /* Repeated from the prose on purpose: the SVG copies are decorative and
       hidden from assistive technology. */
    captions: [
      'Which treatment works best?',
      'What happens to patients like me?',
      'Is this treatment safe?',
      'Who benefits, and who does not?'
    ]
  },
  { id: 'study',    label: 'A study',     captions: ['A question becomes a protocol'] },
  { id: 'network',  label: 'The network', captions: ['Code travels outward', 'Records never leave'] },
  { id: 'evidence', label: 'Results',     captions: ['Aggregate results return'] },
  { id: 'commons',  label: 'The commons', captions: ['One study among many'] },
  { id: 'loop',     label: 'The loop',    captions: ['Better questions'] }
];
