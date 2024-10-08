import Link from "next/link";
import { Route } from "next";
import { HiArrowLongRight } from "react-icons/hi2";

const Size = {
  xs: {
    link: "text-xs",
    icon: "ml-2 -mr-1 w-3 h-3",
    border: "border-b-[0.5px]",
  },
  sm: { link: "text-sm", icon: "ml-2 -mr-1 w-4 h-4", border: "border-b" },
  md: {
    link: "text-md",
    icon: "ml-2 -mr-1 w-5 h-5",
    border: "border-b-[1.5px]",
  },
  lg: { link: "text-lg", icon: "ml-2 -mr-1 w-6 h-6", border: "border-b-2" },
  xl: {
    link: "text-xl",
    icon: "ml-2 -mr-1 w-8 h-8",
    border: "border-b-[2.5px]",
  },
};

type SizeKey = keyof typeof Size;

export default function ActionLink({
  size = "md",
  children,
  href,
  color = "accent-500",
  transitionColor,
  border = true,
}: {
  size?: SizeKey;
  children: React.ReactNode;
  href: URL | Route<string>;
  color?: string;
  transitionColor?: string;
  border?: boolean;
}) {
  // XXX: There seems to be a Tailwind bug where the border color is not
  // being applied below. The CSS checks out but the color defaults to gray.
  const linkClasses = `
    group inline-flex justify-center items-center py-2 font-semibold
    tracking-tight font-medium
    text-${color}
    ${Size[size].link}
    ${border && `${Size[size].border} border-current`}
    ${(transitionColor && `hover:text-${transitionColor}`) || ""}
    ${border && transitionColor ? `hover:border-${transitionColor}` : ""}
  `;

  const iconClasses = `
    group-hover:translate-x-1 group-hover:scale-110 duration-50 transform transition
    ${(transitionColor && `group-hover:text-${transitionColor}`) || ""}
    ${Size[size].icon}
  `;

  return (
    <Link href={href} className={linkClasses}>
      {children}
      <HiArrowLongRight className={iconClasses} />
    </Link>
  );
}
