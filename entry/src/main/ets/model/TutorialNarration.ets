export interface TutorialClip {
  id: string;
  text: string;
}

export const TUTORIAL_CLIPS: TutorialClip[] = [
  { id: 'goal', text: '猜出隐藏的数字和顺序，就能破解密码。数字从零到九中选，不能重复，第一位也可以是零。' },
  { id: 'demo', text: '演示答案是五、二、三、四，猜测是五、三、四、六。点击看讲解，认识正位。' },
  { id: 'exact', text: '五在两组数字中都是第一位。数字和位置都对，叫正位。这次正位一个。' },
  { id: 'misplaced', text: '三和四都在答案里，位置却错了，所以错位两个。五不重复计算，六不在答案里。' },
  { id: 'summary', text: '正位一个，错位两个。正式对局只给数量，不指出哪些数字、哪些位置正确。逐位标记只用于演示。' },
  { id: 'strategy', text: '正位、错位都是零，就能排除这组数字。再想想：另一局只看到正位一个，能知道哪一位正确吗？' },
  { id: 'quiz_correct', text: '对了！这里的一表示数量，不是第一位。还需要结合其他猜测来推理。' },
  { id: 'quiz_retry', text: '这里的一表示一个，不是第一位。刚才第一位正确，只是演示中的例子。再试一次。' },
  { id: 'practice', text: '现在练三位，规则和四位一样。不限次数，不计战绩。输入三个不重复的数字，输满自动提交。' },
  { id: 'practice_0_0', text: '正位零个，错位零个。这三个数字都不在密码里。下一次换一组数字试试。' },
  { id: 'practice_0_1', text: '正位零个，错位一个。有一个数字在密码里，但位置不对。还不能确定具体是哪一个。' },
  { id: 'practice_0_2', text: '正位零个，错位两个。有两个数字在密码里，但位置都不对。还不能确定具体是哪两个。' },
  { id: 'practice_0_3', text: '正位零个，错位三个。三个数字都找对了，但位置都不对。试着调整它们的顺序。' },
  { id: 'practice_1_0', text: '正位一个，错位零个。有一个数字和位置都正确，另外两个数字不在密码里。还不能确定是哪一位正确。' },
  { id: 'practice_1_1', text: '正位一个，错位一个。两个数字在密码里，其中一个位置正确。但还不能确定具体是哪两个。' },
  { id: 'practice_1_2', text: '正位一个，错位两个。三个数字都找对了，其中一个位置正确。结合之前的线索，继续调整顺序。' },
  { id: 'practice_2_0', text: '正位两个，错位零个。有两个数字和位置都正确，还有一个数字需要更换。但这条反馈不告诉你是哪一个。' },
  { id: 'practice_3_0', text: '猜中了！数字和位置全部正确。你已经完成这次练习。' },
  { id: 'ready', text: '正式局三位六次、四位八次、五位十次。提示和人工智能建议也消耗机会。只记录用时，不会超时失败。' }
];

export function tutorialClip(id: string): TutorialClip {
  for (let i = 0; i < TUTORIAL_CLIPS.length; i++) {
    if (TUTORIAL_CLIPS[i].id === id) {
      return TUTORIAL_CLIPS[i];
    }
  }
  return TUTORIAL_CLIPS[0];
}

export function practiceClip(exact: number, misplaced: number): TutorialClip {
  return tutorialClip('practice_' + exact.toString() + '_' + misplaced.toString());
}
