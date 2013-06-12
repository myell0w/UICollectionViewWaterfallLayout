//
//  UICollectionViewWaterfallLayout.m
//
//  Created by Nelson on 12/11/19.
//  Copyright (c) 2012 Nelson Tai. All rights reserved.
//

#import "MTDCollectionViewWaterfallLayout.h"

@interface MTDCollectionViewWaterfallLayout()

@property (nonatomic, assign) NSInteger itemCount;
@property (nonatomic, assign) CGFloat interitemSpacing;
@property (nonatomic, strong) NSMutableArray *columnHeights; // height for each column
@property (nonatomic, strong) NSMutableArray *itemAttributes; // attributes for each item

@property (nonatomic, strong) NSSet *indexPathsToInsert;
@property (nonatomic, strong) NSSet *indexPathsToDelete;

@end

@implementation MTDCollectionViewWaterfallLayout

#pragma mark - Accessors
- (void)setColumnCount:(NSUInteger)columnCount
{
    if (_columnCount != columnCount) {
        _columnCount = columnCount;
        [self invalidateLayout];
    }
}

- (void)setItemWidth:(CGFloat)itemWidth
{
    if (_itemWidth != itemWidth) {
        _itemWidth = itemWidth;
        [self invalidateLayout];
    }
}

- (void)setSectionInset:(UIEdgeInsets)sectionInset
{
    if (!UIEdgeInsetsEqualToEdgeInsets(_sectionInset, sectionInset)) {
        _sectionInset = sectionInset;
        [self invalidateLayout];
    }
}

#pragma mark - Init
- (void)commonInit
{
    _columnCount = 2;
    _itemWidth = 140.0f;
    _sectionInset = UIEdgeInsetsZero;
}

- (id)init
{
    self = [super init];
    if (self) {
        [self commonInit];
    }
    return self;
}

#pragma mark - Life cycle
- (void)dealloc
{
    [_columnHeights removeAllObjects];
    _columnHeights = nil;

    [_itemAttributes removeAllObjects];
    _itemAttributes = nil;
}

#pragma mark - Methods to Override
- (void)prepareLayout
{
    [super prepareLayout];

    if ([[self collectionView] numberOfSections] > 0) {
        _itemCount = [[self collectionView] numberOfItemsInSection:0];

        NSAssert(_columnCount > 1, @"columnCount for UICollectionViewWaterfallLayout should be greater than 1.");
        CGFloat width = self.collectionView.frame.size.width - _sectionInset.left - _sectionInset.right;
        _interitemSpacing = floorf((width - _columnCount * _itemWidth) / (_columnCount - 1));

        _itemAttributes = [NSMutableArray arrayWithCapacity:_itemCount];
        _columnHeights = [NSMutableArray arrayWithCapacity:_columnCount];
        for (NSInteger idx = 0; idx < _columnCount; idx++) {
            [_columnHeights addObject:@(_sectionInset.top)];
        }

        // Item will be put into shortest column.
        for (NSInteger idx = 0; idx < _itemCount; idx++) {
            NSIndexPath *indexPath = [NSIndexPath indexPathForItem:idx inSection:0];
            CGFloat itemHeight = [self.delegate collectionView:self.collectionView
                                                        layout:self
                                      heightForItemAtIndexPath:indexPath];
            NSUInteger columnIndex = [self shortestColumnIndex];
            CGFloat xOffset = _sectionInset.left + (_itemWidth + _interitemSpacing) * columnIndex;
            CGFloat yOffset = [(_columnHeights[columnIndex]) floatValue];

            UICollectionViewLayoutAttributes *attributes =
            [UICollectionViewLayoutAttributes layoutAttributesForCellWithIndexPath:indexPath];
            attributes.frame = CGRectMake(xOffset, yOffset, self.itemWidth, itemHeight);
            attributes.transform3D = CATransform3DIdentity;
            [_itemAttributes addObject:attributes];
            _columnHeights[columnIndex] = @(yOffset + itemHeight + _interitemSpacing);
        }
    }
}

- (CGSize)collectionViewContentSize
{
    if (self.itemCount == 0) {
        return CGSizeZero;
    }

    CGSize contentSize = self.collectionView.frame.size;
    NSUInteger columnIndex = [self longestColumnIndex];
    CGFloat height = [self.columnHeights[columnIndex] floatValue];
    contentSize.height = height - self.interitemSpacing + self.sectionInset.bottom;
    return contentSize;
}

- (UICollectionViewLayoutAttributes *)layoutAttributesForItemAtIndexPath:(NSIndexPath *)path
{
    return (self.itemAttributes)[path.item];
}

- (UICollectionViewLayoutAttributes *)initialLayoutAttributesForAppearingItemAtIndexPath:(NSIndexPath *)itemIndexPath {
    if ([self.indexPathsToInsert containsObject:itemIndexPath]) {
        return [self layoutAttributesForAppearingOrDisappearingItemAtIndexPath:itemIndexPath];
    } else {
        return [self layoutAttributesForItemAtIndexPath:itemIndexPath];
    }
}

//- (UICollectionViewLayoutAttributes *)finalLayoutAttributesForDisappearingItemAtIndexPath:(NSIndexPath *)itemIndexPath {
//    if ([self.indexPathsToDelete containsObject:itemIndexPath]) {
//        return [self layoutAttributesForAppearingOrDisappearingItemAtIndexPath:itemIndexPath];
//    } else {
//        return [self layoutAttributesForItemAtIndexPath:itemIndexPath];
//    }
//}

// Private method: we want the same animation when inserting/deleting, just reversed
- (UICollectionViewLayoutAttributes *)layoutAttributesForAppearingOrDisappearingItemAtIndexPath:(NSIndexPath *)itemIndexPath {
    UICollectionViewLayoutAttributes *attributes = [self layoutAttributesForItemAtIndexPath:itemIndexPath];

    attributes.transform3D = CATransform3DMakeScale(1/100.f, 1/100.f, 1.f);
    attributes.alpha = 0.f;

    return attributes;
}

- (NSArray *)layoutAttributesForElementsInRect:(CGRect)rect
{
    return [self.itemAttributes filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(UICollectionViewLayoutAttributes *evaluatedObject, NSDictionary *bindings) {
        return CGRectIntersectsRect(rect, [evaluatedObject frame]);
    }]];
}

- (BOOL)shouldInvalidateLayoutForBoundsChange:(CGRect)newBounds
{
    return NO;
}

// we keep track of the indexPaths of the objects that are actually appearing/disappearing
// because initialLayoutAttributesForAppearingItemAtIndexPath: and finalLayoutAttributesForAppearingItemAtIndexPath:
// get called for every item, not only the appearing/disappearing ones
- (void)prepareForCollectionViewUpdates:(NSArray *)updateItems {
    [super prepareForCollectionViewUpdates:updateItems];

    NSUInteger capacity = updateItems.count/3; // rough expectation
    NSMutableSet *insertions = [[NSMutableSet alloc] initWithCapacity:capacity];
    NSMutableSet *deletions = [[NSMutableSet alloc] initWithCapacity:capacity];

    for (MTDCollectionViewUpdateItem *item in updateItems) {
        if (item.updateAction == UICollectionUpdateActionInsert) {
            [insertions addObject:item.indexPathAfterUpdate];
        } else if (item.updateAction == UICollectionUpdateActionDelete) {
            [deletions addObject:item.indexPathBeforeUpdate];
        }
    }

    self.indexPathsToInsert = insertions;
    self.indexPathsToDelete = deletions;
}

- (void)finalizeCollectionViewUpdates {
    [super finalizeCollectionViewUpdates];

    self.indexPathsToInsert = nil;
    self.indexPathsToDelete = nil;
}

#pragma mark - Private Methods
// Find out shortest column.
- (NSUInteger)shortestColumnIndex
{
    __block NSUInteger index = 0;
    __block CGFloat shortestHeight = MAXFLOAT;

    [self.columnHeights enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        CGFloat height = [obj floatValue];
        if (height < shortestHeight) {
            shortestHeight = height;
            index = idx;
        }
    }];

    return index;
}

// Find out longest column.
- (NSUInteger)longestColumnIndex
{
    __block NSUInteger index = 0;
    __block CGFloat longestHeight = 0;

    [self.columnHeights enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        CGFloat height = [obj floatValue];
        if (height > longestHeight) {
            longestHeight = height;
            index = idx;
        }
    }];
    
    return index;
}

@end
