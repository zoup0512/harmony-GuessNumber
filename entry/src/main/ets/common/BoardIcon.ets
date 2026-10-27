import { Theme } from './Theme';

@Component
export struct BoardIcon {
  kind: string = 'grid';
  iconSize: number = 20;
  color: ResourceColor = Theme.TEXT_SUB;

  private commands(): string {
    switch (this.kind) {
      case 'clock':
        return 'M12 3 A9 9 0 1 1 11.99 3 M12 7 L12 12 L15.5 14';
      case 'hint':
        return 'M8 16 C8 13 5.5 12 5.5 8.5 A6.5 6.5 0 0 1 18.5 8.5 C18.5 12 16 13 16 16 Z M9 19 L15 19 M10 22 L14 22';
      case 'analysis':
        return 'M4 4 L20 4 L20 20 L4 20 Z M8 15 L8 12 M12 15 L12 8 M16 15 L16 10';
      case 'check':
        return 'M5 12 L10 17 L19 7';
      case 'keyboard':
        return 'M3 6 L21 6 L21 18 L3 18 Z M7 10 L7.1 10 M12 10 L12.1 10 M17 10 L17.1 10 M7 14 L17 14';
      case 'flag':
        return 'M6 21 L6 3 L18 3 L16 7 L18 11 L6 11';
      default:
        return 'M4 4 L10 4 L10 10 L4 10 Z M14 4 L20 4 L20 10 L14 10 Z M4 14 L10 14 L10 20 L4 20 Z M14 14 L20 14 L20 20 L14 20 Z';
    }
  }

  build() {
    Shape() {
      Path()
        .commands(this.commands())
        .fill(Color.Transparent)
        .stroke(this.color)
        .strokeWidth('1.8px')
        .strokeLineCap(LineCapStyle.Round)
        .strokeLineJoin(LineJoinStyle.Round)
    }
    .viewPort({ x: '0px', y: '0px', width: '24px', height: '24px' })
    .width(this.iconSize)
    .height(this.iconSize)
    .accessibilityLevel('no')
  }
}
